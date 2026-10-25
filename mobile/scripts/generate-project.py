#!/usr/bin/env python3
"""Generate a deterministic Xcode project without requiring third-party tooling."""
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
local = ROOT / "signing.local.json"
signing = json.loads(local.read_text()) if local.is_file() else {}
app_identifier = signing.get("bundleIdentifier", "com.wisprm.mobile")
app_group = signing.get("appGroup", "group.com.wisprm.mobile")
team = os.environ.get("WISPRM_DEVELOPMENT_TEAM") or signing.get("developmentTeam", "")
objects = {}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def obj(label, isa, **values):
    key = uid(label); objects[key] = dict(isa=isa, **values); return key
def group(name, children): return obj(name, "PBXGroup", children=children, sourceTree="<group>")
def encode(value):
    if isinstance(value, dict): return "{\n" + "\n".join(f"{json.dumps(str(k))} = {encode(v)};" for k,v in value.items()) + "\n}"
    if isinstance(value, list): return "(" + ",".join(encode(v) for v in value) + ")"
    return json.dumps(str(value))

project = uid("project")
packages = {}
packages["mobilecore"] = obj("package-mobilecore", "XCLocalSwiftPackageReference", relativePath="MobileCore")
packages["wisprcore"] = obj("package-wisprcore", "XCLocalSwiftPackageReference", relativePath="../desktop")
packages["inference"] = obj("package-inference", "XCLocalSwiftPackageReference", relativePath="MobileInference")

files = []
def file(path, kind):
    value = obj("file-"+path, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="<group>")
    if value not in files: files.append(value)
    return value
products = []
targets = []
for name, folder, identifier, product_type in [
    ("wisprM", "App", app_identifier, "com.apple.product-type.application"),
    ("WisprKeyboard", "Keyboard", app_identifier + ".keyboard", "com.apple.product-type.app-extension")
]:
    extension = folder == "Keyboard"
    sources = [obj(name+"-source-"+str(p.relative_to(ROOT)), "PBXBuildFile", fileRef=file(str(p.relative_to(ROOT)), "sourcecode.swift"))
               for p in sorted((ROOT/folder).glob("*.swift"))]
    source_phase = obj(name+"-sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=sources, runOnlyForDeploymentPostprocessing=0)
    dependencies = [("WisprMobileCore", "mobilecore")]
    if not extension: dependencies += [("WisprCore", "wisprcore"), ("WisprMobileInference", "inference")]
    package_products, frameworks = [], []
    for product_name, package in dependencies:
        ref = obj(name+"-product-"+product_name, "XCSwiftPackageProductDependency", package=packages[package], productName=product_name)
        package_products.append(ref)
        frameworks.append(obj(name+"-framework-"+product_name, "PBXBuildFile", productRef=ref))
    framework_phase = obj(name+"-frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=frameworks, runOnlyForDeploymentPostprocessing=0)
    resources = []
    resources.append(obj(name+"-privacy", "PBXBuildFile", fileRef=file("Resources/PrivacyInfo.xcprivacy", "text.xml")))
    if not extension:
        resources.append(obj("assets-build", "PBXBuildFile", fileRef=file("Resources/Assets.xcassets", "folder.assetcatalog")))
    resource_phase = obj(name+"-resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)
    product = obj(name+"-output", "PBXFileReference", explicitFileType="wrapper.app-extension" if extension else "wrapper.application",
                  path=name+(".appex" if extension else ".app"), sourceTree="BUILT_PRODUCTS_DIR", includeInIndex=0)
    products.append(product)
    configurations = []
    for mode in ["Debug", "Release"]:
        settings = dict(PRODUCT_BUNDLE_IDENTIFIER=identifier, PRODUCT_NAME="$(TARGET_NAME)",
            DEVELOPMENT_TEAM=team, WISPRM_APP_GROUP=app_group,
            INFOPLIST_FILE=f"Resources/{name}-Info.plist", CODE_SIGN_ENTITLEMENTS=f"Resources/{name}.entitlements",
            CODE_SIGN_STYLE="Automatic", SWIFT_VERSION="5.0", IPHONEOS_DEPLOYMENT_TARGET="17.0",
            TARGETED_DEVICE_FAMILY="1,2", SUPPORTED_PLATFORMS="iphoneos iphonesimulator", SDKROOT="iphoneos",
            GENERATE_INFOPLIST_FILE="NO", CURRENT_PROJECT_VERSION="1", MARKETING_VERSION="0.1.0",
            LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
            SWIFT_EMIT_LOC_STRINGS="YES")
        if extension: settings.update(APPLICATION_EXTENSION_API_ONLY="YES", SKIP_INSTALL="YES")
        else: settings.update(ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon")
        configurations.append(obj(name+mode, "XCBuildConfiguration", name=mode, buildSettings=settings))
    config = obj(name+"-configs", "XCConfigurationList", buildConfigurations=configurations, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
    phases = [source_phase, framework_phase, resource_phase]
    target_dependencies = []
    if not extension:
        proxy = obj("keyboard-proxy", "PBXContainerItemProxy", containerPortal=project, proxyType=1, remoteGlobalIDString=uid("target-WisprKeyboard"), remoteInfo="WisprKeyboard")
        target_dependencies.append(obj("keyboard-dependency", "PBXTargetDependency", target=uid("target-WisprKeyboard"), targetProxy=proxy))
        embed = obj("keyboard-embed-file", "PBXBuildFile", fileRef=uid("WisprKeyboard-output"), settings={"ATTRIBUTES":["RemoveHeadersOnCopy"]})
        phases.append(obj("embed-extensions", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=13, files=[embed], name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0))
    targets.append(obj("target-"+name, "PBXNativeTarget", name=name, productName=name, buildConfigurationList=config,
                       buildPhases=phases, buildRules=[], dependencies=target_dependencies, productReference=product,
                       productType=product_type, packageProductDependencies=package_products))

product_group = group("products", products)
main_group = group("main", files+[product_group])
configs = []
for mode in ["Debug", "Release"]:
    configs.append(obj("project-"+mode, "XCBuildConfiguration", name=mode, buildSettings=dict(
        CLANG_ENABLE_MODULES="YES", SWIFT_OPTIMIZATION_LEVEL="-Onone" if mode=="Debug" else "-O",
        DEBUG_INFORMATION_FORMAT="dwarf" if mode=="Debug" else "dwarf-with-dsym",
        SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG" if mode=="Debug" else "", ENABLE_USER_SCRIPT_SANDBOXING="YES")))
configuration_list = obj("project-configs", "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
obj("project", "PBXProject", attributes={"LastUpgradeCheck":"2650", "BuildIndependentTargetsInParallel":"YES"},
    buildConfigurationList=configuration_list, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0,
    knownRegions=["en","Base"], mainGroup=main_group, productRefGroup=product_group,
    projectDirPath="", projectRoot="", targets=targets, packageReferences=list(packages.values()))

destination = ROOT/"wisprM.xcodeproj"
destination.mkdir(exist_ok=True)
(destination/"project.pbxproj").write_text("// !$*UTF8*$!\n"+encode(dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project))+"\n")
schemes = destination/"xcshareddata/xcschemes"; schemes.mkdir(parents=True, exist_ok=True)
(schemes/"wisprM.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2650" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target-wisprM')}" BuildableName="wisprM.app" BlueprintName="wisprM" ReferencedContainer="container:wisprM.xcodeproj"/></BuildActionEntry>
</BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target-wisprM')}" BuildableName="wisprM.app" BlueprintName="wisprM" ReferencedContainer="container:wisprM.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print(destination)
