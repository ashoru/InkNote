#!/usr/bin/env python3
"""Generate InkNote.xcodeproj/project.pbxproj by scanning Sources/.

Usage: python3 tools/generate_project.py
Run from the InkNote project root (the directory containing Sources/).

The script is deterministic: object IDs are the first 24 hex digits of
the MD5 of the file's project-relative path, so regenerating the
project does not churn unrelated IDs. Hand-editing project.pbxproj
is discouraged; edit Sources/ and re-run this script instead.
"""
import hashlib
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
PROJECT_DIR = ROOT / "InkNote.xcodeproj"
PBXPROJ = PROJECT_DIR / "project.pbxproj"


def pbx_id(path: str) -> str:
    return hashlib.md5(path.encode()).hexdigest()[:24].upper()


def main() -> int:
    swift_files = sorted(str(p.relative_to(ROOT)) for p in SOURCES.glob("*.swift"))
    if not swift_files:
        print("No Swift files found in Sources/", file=sys.stderr)
        return 1

    build_files = []
    file_refs = []
    for rel in swift_files:
        fid = pbx_id("fileref:" + rel)
        bid = pbx_id("buildfile:" + rel)
        name = pathlib.Path(rel).name
        file_refs.append(
            f"\t\t{fid} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};"
        )
        build_files.append(
            f"\t\t{bid} = {{isa = PBXBuildFile; fileRef = {fid}; }};"
        )

    sources_phase_id = pbx_id("sourcesphase")
    sources_lines = ",\n".join(f"\t\t\t\t{pbx_id('buildfile:' + rel)}" for rel in swift_files)
    group_children = ",\n".join(f"\t\t\t\t{pbx_id('fileref:' + rel)}" for rel in swift_files)

    target_id = pbx_id("target:InkNote")
    project_id = pbx_id("project:InkNote")
    main_group_id = pbx_id("group:main")
    sources_group_id = pbx_id("group:Sources")
    products_group_id = pbx_id("group:Products")
    app_ref_id = pbx_id("fileref:InkNote.app")
    debug_config_id = pbx_id("config:Debug")
    release_config_id = pbx_id("config:Release")
    project_debug_id = pbx_id("projectconfig:Debug")
    project_release_id = pbx_id("projectconfig:Release")
    target_debug_id = pbx_id("targetconfig:Debug")
    target_release_id = pbx_id("targetconfig:Release")
    project_list_id = pbx_id("configlist:project")
    target_list_id = pbx_id("configlist:target")

    content = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

\t\t/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
\t\t/* End PBXBuildFile section */

\t\t/* Begin PBXFileReference section */
{chr(10).join(file_refs)}
\t\t{app_ref_id} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = InkNote.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t/* End PBXFileReference section */

\t\t/* Begin PBXFrameworksBuildPhase section */
\t\t{pbx_id("frameworksphase")} = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t/* End PBXFrameworksBuildPhase section */

\t\t/* Begin PBXGroup section */
\t\t{main_group_id} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{sources_group_id},
\t\t\t\t{products_group_id},
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{sources_group_id} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{group_children},
\t\t\t);
\t\t\tpath = Sources;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{products_group_id} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{app_ref_id},
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t/* End PBXGroup section */

\t\t/* Begin PBXNativeTarget section */
\t\t{target_id} = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {target_list_id};
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase_id},
\t\t\t\t{pbx_id("frameworksphase")},
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = InkNote;
\t\t\tproductName = InkNote;
\t\t\tproductReference = {app_ref_id};
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t/* End PBXNativeTarget section */

\t\t/* Begin PBXProject section */
\t\t{project_id} = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastUpgradeCheck = 2600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{target_id} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.6;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {project_list_id};
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group_id};
\t\t\tproductRefGroup = {products_group_id};
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{target_id},
\t\t\t);
\t\t}};
\t\t/* End PBXProject section */

\t\t/* Begin PBXSourcesBuildPhase section */
\t\t{sources_phase_id} = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{sources_lines},
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t/* End PBXSourcesBuildPhase section */

\t\t/* Begin XCBuildConfiguration section */
\t\t{project_debug_id} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 2;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 18.0;
\t\t\t\tLOCALIZATION_PREFS = "";
\t\t\t\tMARKETING_VERSION = 0.1.1;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_EMBED_LIBRARIES_WITH_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{project_release_id} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 2;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 18.0;
\t\t\t\tLOCALIZATION_PREFS = "";
\t\t\t\tMARKETING_VERSION = 0.1.1;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_EMBED_LIBRARIES_WITH_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{target_debug_id} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGNING_ALLOWED = NO;
\t\t\t\tCODE_SIGN_IDENTITY = "";
\t\t\t\tCODE_SIGN_STYLE = Manual;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UIRequiresFullScreen = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchStoryboardName = "";
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.ashoru.inknote;
\t\t\t\tPRODUCT_NAME = InkNote;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{target_release_id} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGNING_ALLOWED = NO;
\t\t\t\tCODE_SIGN_IDENTITY = "";
\t\t\t\tCODE_SIGN_STYLE = Manual;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UIRequiresFullScreen = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchStoryboardName = "";
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.ashoru.inknote;
\t\t\t\tPRODUCT_NAME = InkNote;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t/* End XCBuildConfiguration section */

\t\t/* Begin XCConfigurationList section */
\t\t{project_list_id} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{project_debug_id},
\t\t\t\t{project_release_id},
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{target_list_id} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{target_debug_id},
\t\t\t\t{target_release_id},
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t/* End XCConfigurationList section */
\t}};
\trootObject = {project_id};
}}
"""
    PROJECT_DIR.mkdir(parents=True, exist_ok=True)
    PBXPROJ.write_text(content)
    print(f"Wrote {PBXPROJ} with {len(swift_files)} Swift files:")
    for rel in swift_files:
        print(f"  {rel}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
