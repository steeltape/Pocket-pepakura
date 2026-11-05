# Pocket Pepakura — Automatic Android debug APK build

This is the v5 source project **plus** an Android export preset and GitHub Actions workflow.
It is **not** an APK. The build has not run yet. The `Godot` scripts and exported
Android application still need validation on a real runner/device.

## Steps (no Android Studio required)

1. Open GitHub and create a repository for this project. A private repository is fine.
2. Unzip this package. Upload **the contents of `PocketPepakura_AutoBuild`** into the repository root,
   preserving the hidden `.github/workflows/build-apk.yml` file and `scripts/` folder.
   `project.godot` must be at the repository root.
3. In GitHub, open **Actions → Build Pocket Pepakura Android APK → Run workflow**.
   The workflow also starts on pushes to the `main` or `master` branch.
4. If the build succeeds, open that run's **Artifacts** section and download
   `PocketPepakura-Android-debug`. Unzip the artifact: it contains `PocketPepakura-v5-debug.apk`.
5. Transfer the APK to your Android phone or tablet and open it to install.

## Technical details

- Godot 4.6, `barichello/godot-ci:4.6` Linux build image, matching export templates and Android SDK.
- 64-bit ARM Android debug APK. It will not install on devices that only support 32-bit ARM.
- Debug-signed with the container image's generated debug key; not Play Store ready.
- App package ID: `com.pocketpepakura.viewer`.
- Workflow validates GDScript at import and checks APK archive integrity.
- Workflow has **not** been executed here, so success is not guaranteed; see its logs for build errors.
- Your personal .pdo files are **not** included in this ZIP; open them with the file picker after installing.
- Later upgrades may use a different debug signing key; Android may require uninstalling the earlier debug build.
