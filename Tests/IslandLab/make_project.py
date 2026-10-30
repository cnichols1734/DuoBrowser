"""Build-only simulator companion. Generates its project/products under ignored work/."""
import pathlib
import plistlib

root = pathlib.Path(__file__).resolve().parents[2]
output = root / 'work' / 'island-lab'
project = output / 'IslandLab.xcodeproj'
project.mkdir(parents=True, exist_ok=True)
objects = {}

def obj(kind, **fields):
    key = f'{len(objects)+1:024X}'
    objects[key] = {'isa': kind, **fields}
    return key

def configs(settings):
    builds = [obj('XCBuildConfiguration', name=name, buildSettings=settings) for name in ('Debug', 'Release')]
    return obj('XCConfigurationList', buildConfigurations=builds, defaultConfigurationIsVisible=0, defaultConfigurationName='Debug')

sources = {name: obj('PBXFileReference', lastKnownFileType='sourcecode.swift', path=str(root/'Tests'/'IslandLab'/name), sourceTree='<absolute>')
           for name in ('IslandActivity.swift','IslandLabApp.swift','IslandWidget.swift')}
products = obj('PBXGroup', children=[], name='Products', sourceTree='<group>')
group = obj('PBXGroup', children=list(sources.values())+[products], sourceTree='<group>')
common = {'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'27.1','SWIFT_VERSION':'6.0','TARGETED_DEVICE_FAMILY':'1,2',
          'CODE_SIGNING_ALLOWED':'NO','SUPPORTED_PLATFORMS':'iphonesimulator','SWIFT_OPTIMIZATION_LEVEL':'-Onone',
          'SWIFT_STRICT_CONCURRENCY':'complete','ALWAYS_SEARCH_USER_PATHS':'NO'}
targets = []
for name, source, suffix, product_type in [('IslandWidget','IslandWidget.swift','appex','app-extension'),('IslandLab','IslandLabApp.swift','app','application')]:
    info = {'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleExecutable':'$(EXECUTABLE_NAME)', 'CFBundleName':name,
            'CFBundleDisplayName':'Island Lab', 'CFBundleVersion':'1','CFBundleShortVersionString':'1.0',
            'CFBundlePackageType':'XPC!' if suffix=='appex' else 'APPL'}
    if suffix=='appex': info['NSExtension']={'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}
    else:
        info.update(NSSupportsLiveActivities=True, UILaunchScreen={}, UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes':False})
    info_path=output/(name+'-Info.plist')
    info_path.write_bytes(plistlib.dumps(info))
    settings={**common,'PRODUCT_NAME':name,'PRODUCT_BUNDLE_IDENTIFIER':'dev.local.DuoBrowser.IslandLab'+('.Widget' if suffix=='appex' else ''),
              'INFOPLIST_FILE':str(info_path), 'SKIP_INSTALL':'YES' if suffix=='appex' else 'NO', 'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'}
    if suffix=='appex': settings['APPLICATION_EXTENSION_API_ONLY']='YES'
    product=obj('PBXFileReference', explicitFileType='wrapper.app-extension' if suffix=='appex' else 'wrapper.application', path=name+'.'+suffix, sourceTree='BUILT_PRODUCTS_DIR')
    objects[products]['children'].append(product)
    phase=obj('PBXSourcesBuildPhase', buildActionMask=2147483647, files=[obj('PBXBuildFile',fileRef=sources[n]) for n in ('IslandActivity.swift',source)], runOnlyForDeploymentPostprocessing=0)
    phases=[phase]
    dependencies=[]
    if suffix=='app':
        phases.append(obj('PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,
                          files=[obj('PBXBuildFile',fileRef=widget_product,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0))
        dependencies.append(obj('PBXTargetDependency',target=targets[0]))
    target=obj('PBXNativeTarget',buildConfigurationList=configs(settings),buildPhases=phases,buildRules=[],dependencies=dependencies,name=name,productName=name,productReference=product,productType='com.apple.product-type.'+product_type)
    targets.append(target)
    if suffix=='appex': widget_product=product
project_id=obj('PBXProject',attributes={'LastUpgradeCheck':'2710'},buildConfigurationList=configs(common),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=targets)
(project/'project.pbxproj').write_bytes(plistlib.dumps({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':project_id}))
print(project)
