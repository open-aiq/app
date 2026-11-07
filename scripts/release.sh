#!/usr/bin/env bash
# Bump the pubspec version, build the signed release APK, push the release
# commit and tag, and publish a GitHub release with the APK attached.
set -euo pipefail

RELEASE_BRANCH="${RELEASE_BRANCH:-main}"
DIST="${DIST:-dist}"
FLUTTER="${FLUTTER:-flutter}"
ENV_FILE="env/production.json"

die() {
	echo "error: $*" >&2
	exit 1
}

command -v gh >/dev/null 2>&1 || die "gh CLI not found: https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "gh not authenticated. Run: gh auth login"
[ -f android/key.properties ] ||
	die "android/key.properties is missing; run 'make keystore' and see android/key.properties.example"

branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "$RELEASE_BRANCH" ] ||
	die "releases must be cut from '$RELEASE_BRANCH' (you are on '$branch')"

git diff-index --quiet HEAD -- ||
	die "working tree is dirty; commit or stash changes first"

# pubspec.yaml holds "version: <semver>+<build number>".
pubspec_version="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml)"
[ -n "$pubspec_version" ] || die "no version line in pubspec.yaml"
current="v${pubspec_version%%+*}"
choice="${1:-${RELEASE_VERSION:-}}"
if [ -z "$choice" ]; then
	read -rp "Current version: $current
Bump type or version [major/minor/patch/x.y.z]: " choice
fi

case "$choice" in
	major | minor | patch)
		version="${current#v}"
		major="${version%%.*}"
		rest="${version#*.}"
		minor="${rest%%.*}"
		patch="${rest#*.}"
		patch="${patch%%-*}"
		case "$choice" in
			major) major=$((major + 1)); minor=0; patch=0 ;;
			minor) minor=$((minor + 1)); patch=0 ;;
			patch) patch=$((patch + 1)) ;;
		esac
		next="v${major}.${minor}.${patch}"
		;;
	*)
		next="v${choice#v}"
		[[ "$next" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] ||
			die "invalid version '$choice' (expected major, minor, patch, or a semantic version)"
		;;
esac

git rev-parse "$next" >/dev/null 2>&1 && die "tag $next already exists"

# Major and minor versions must be registered at docs.air-iq.net/versions.json
# (open-aiq/docs src/data/versions.json) before they can be released.
bash scripts/check-version-registry.sh app "$next"

# Android versionCode / iOS CFBundleVersion must grow with every release, so
# derive it from the version: 1.2.3 -> 10203. Pre-releases share the number
# of their final version.
build_name="${next#v}"
core="${build_name%%-*}"
IFS=. read -r b_major b_minor b_patch <<<"$core"
[ "$b_minor" -lt 100 ] && [ "$b_patch" -lt 100 ] ||
	die "minor and patch must be below 100 to derive the build number"
build_number=$((b_major * 10000 + b_minor * 100 + b_patch))
[ "$build_number" -ge 1 ] || die "version $next gives build number 0; use at least 0.0.1"

read -rp "Release $next (build $build_number) from $branch? [y/N]: " confirm
case "$confirm" in
	y | Y) ;;
	*) die "aborted" ;;
esac

echo "==> Verifying release"
make verify

# The Settings screen shows AppConfig.appVersion; set it before building so
# the APK carries the version it's released as.
sed -i.bak "s/static const appVersion = '[^']*';/static const appVersion = '${build_name}';/" lib/config.dart
rm -f lib/config.dart.bak

echo "==> Building signed APK"
"$FLUTTER" build apk --release \
	--build-name="$build_name" \
	--build-number="$build_number" \
	--dart-define-from-file="$ENV_FILE"

rm -rf "$DIST"
mkdir -p "$DIST"
apk="open-aiq-${next}.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$DIST/$apk"
(
	cd "$DIST"
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$apk" >SHA256SUMS
	else
		sha256sum "$apk" >SHA256SUMS
	fi
)

echo "==> Bumping version"
sed -i.bak "s/^version:.*/version: ${build_name}+${build_number}/" pubspec.yaml
rm -f pubspec.yaml.bak
if ! git diff --quiet -- pubspec.yaml lib/config.dart; then
	git add pubspec.yaml lib/config.dart
	git commit -m "Release $next"
fi
git tag -a "$next" -m "Release $next"

echo "==> Pushing $next"
git push --atomic origin "$branch" "$next"

echo "==> Creating GitHub release"
gh release create "$next" \
	--title "$next" \
	--target "$branch" \
	--generate-notes \
	"$DIST"/*

echo "==> Refreshing the releases page on docs.air-iq.net"
gh workflow run deploy.yml --repo open-aiq/docs >/dev/null 2>&1 ||
	echo "warning: could not start the docs deploy; run it from open-aiq/docs Actions so the release is listed" >&2

echo "==> Done: $next published with $apk."
