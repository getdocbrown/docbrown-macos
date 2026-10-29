#!/usr/bin/env python3
"""Generate the Xcode project and its pinned Sparkle dependency."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parent.parent
project = root / 'DocBrown.xcodeproj'
project.mkdir(exist_ok=True)
def ident(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def quote(s): return '"' + str(s).replace('"', '\\"') + '"'
objects = []
def obj(name, content):
    objects.append(f'{ident(name)} = {{ {content} }};')
    return ident(name)
files = sorted((root/'Sources/DocBrown').glob('*.swift')) + sorted((root/'Sources/DocBrownCore').glob('*.swift'))
refs=[]; builds=[]
for file in files:
    rel=str(file.relative_to(root))
    refs.append(obj(rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(rel)}; sourceTree = SOURCE_ROOT;'))
    builds.append(obj('build:'+rel, f'isa = PBXBuildFile; fileRef = {ident(rel)};'))
icon=obj('icon', 'isa = PBXFileReference; lastKnownFileType = image.icns; path = Resources/AppIcon.icns; sourceTree = SOURCE_ROOT;')
iconBuild=obj('iconBuild', f'isa = PBXBuildFile; fileRef = {icon};')
notices=obj('notices', 'isa = PBXFileReference; lastKnownFileType = text; path = Resources/ThirdPartyNotices.txt; sourceTree = SOURCE_ROOT;')
noticesBuild=obj('noticesBuild', f'isa = PBXBuildFile; fileRef = {notices};')
product=obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = DocBrown.app; sourceTree = BUILT_PRODUCTS_DIR;')
products=obj('products', f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
main=obj('main', f'isa = PBXGroup; children = ({",".join(refs+[icon,notices,products])},); sourceTree = "<group>";')
sources=obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
resources=obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({iconBuild},{noticesBuild},); runOnlyForDeploymentPostprocessing = 0;')
sparklePackage=obj('sparklePackage', 'isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/sparkle-project/Sparkle"; requirement = { kind = exactVersion; version = 2.10.1; };')
sparkleProduct=obj('sparkleProduct', f'isa = XCSwiftPackageProductDependency; package = {sparklePackage}; productName = Sparkle;')
sparkleLink=obj('sparkleLink', f'isa = PBXBuildFile; productRef = {sparkleProduct};')
frameworks=obj('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({sparkleLink},); runOnlyForDeploymentPostprocessing = 0;')
configs=[]
for config in ['Debug','Release']:
    settings = {
      'PRODUCT_BUNDLE_IDENTIFIER':'ai.docbrown.macos', 'PRODUCT_NAME':'DocBrown',
      'INFOPLIST_FILE':'Resources/Info.plist','GENERATE_INFOPLIST_FILE':'NO',
      'SWIFT_VERSION':'5.0','MACOSX_DEPLOYMENT_TARGET':'14.0','SDKROOT':'macosx',
      'SWIFT_INCLUDE_PATHS':'$(SRCROOT)/Sources','OTHER_LDFLAGS':'-lsqlite3',
      'CODE_SIGN_IDENTITY':'-', 'CODE_SIGN_STYLE':'Manual',
      'ENABLE_HARDENED_RUNTIME':'YES','ENABLE_APP_SANDBOX':'NO',
      'CODE_SIGN_ENTITLEMENTS':'Resources/DocBrown.entitlements',
      'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks',
      'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if config=='Debug' else '-O',
      'SWIFT_COMPILATION_MODE':'singlefile' if config=='Debug' else 'wholemodule',
      'ENABLE_DEBUG_DYLIB':'NO','COMBINE_HIDPI_IMAGES':'YES','ONLY_ACTIVE_ARCH':'YES' if config=='Debug' else 'NO'
    }
    configs.append(obj(config, 'isa = XCBuildConfiguration; name = '+config+'; buildSettings = {'+' '.join(f'{k} = {quote(v)};' for k,v in settings.items())+'};'))
configlist=obj('configs',f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
projconfigs=[]
for config in ['Debug','Release']:
    projconfigs.append(obj('project'+config,f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ CLANG_ENABLE_MODULES = YES; }};'))
projectconfiglist=obj('projectconfigs',f'isa = XCConfigurationList; buildConfigurations = ({",".join(projconfigs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target=obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {configlist}; buildPhases = ({sources},{frameworks},{resources},); buildRules = (); dependencies = (); packageProductDependencies = ({sparkleProduct},); name = DocBrown; productName = DocBrown; productReference = {product}; productType = "com.apple.product-type.application";')
proj=obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; }}; buildConfigurationList = {projectconfiglist}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; packageReferences = ({sparklePackage},); targets = ({target},);')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {proj}; }}\n')
scheme=project/'xcshareddata/xcschemes/DocBrown.xcscheme'; scheme.parent.mkdir(parents=True,exist_ok=True)
scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="DocBrown.app" BlueprintName="DocBrown" ReferencedContainer="container:DocBrown.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="DocBrown.app" BlueprintName="DocBrown" ReferencedContainer="container:DocBrown.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
