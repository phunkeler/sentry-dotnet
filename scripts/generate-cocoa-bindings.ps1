# Reference: https://github.com/xamarin/xamarin-macios/blob/main/docs/website/binding_types_reference_guide.md

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootPath = (Get-Item $PSScriptRoot).Parent.FullName
$CocoaSdkPath = "$RootPath/modules/sentry-cocoa/Sentry.framework"
$BindingsPath = "$RootPath/src/Sentry.Bindings.Cocoa"
$BackupPath = "$BindingsPath/obj/_unpatched"

# Ensure running on macOS
if (!$IsMacOS)
{
    Write-Error 'Bindings generation can only be performed on macOS.' `
        -CategoryActivity Error -ErrorAction Stop
}

# Ensure Objective Sharpie is installed
if (!(Get-Command sharpie -ErrorAction SilentlyContinue))
{
    Write-Output 'Objective Sharpie not found. Attempting to install via Homebrew.'
    brew install --cask objectivesharpie

    if (!(Get-Command sharpie -ErrorAction SilentlyContinue))
    {
        Write-Error 'Could not install Objective Sharpie automatically. Try installing from https://aka.ms/objective-sharpie manually.'
    }
}

# Ensure Xamarin is installed (or sharpie won't produce expected output).
if (!(Test-Path '/Library/Frameworks/Xamarin.iOS.framework/Versions/Current/lib/64bits/iOS/Xamarin.iOS.dll'))
{
    Write-Output 'Xamarin.iOS not found. Attempting to install via Homebrew.'
    brew install --cask xamarin-ios

    if (!(Test-Path '/Library/Frameworks/Xamarin.iOS.framework/Versions/Current/lib/64bits/iOS/Xamarin.iOS.dll'))
    {
        Write-Error 'Xamarin.iOS not found. Try installing manually from: https://learn.microsoft.com/en-us/xamarin/ios/get-started/installation/.'
    }
}

# Get iPhone SDK version
$iPhoneSdkVersion = sharpie xcode -sdks | grep -o -m 1 'iphoneos\S*'
Write-Output "iPhoneSdkVersion: $iPhoneSdkVersion"

## Imports in the various header files are provided in the "new" style of:
#     `#import <Sentry/SomeHeader.h>`
# ...instead of:
#     `#import "SomeHeader.h"`
# This causes sharpie to fail resolve those headers
$filesToPatch = Get-ChildItem -Path "$CocoaSdkPath/Headers" -Filter *.h -Recurse | Select-Object -ExpandProperty FullName
foreach ($file in $filesToPatch) {
    if (Test-Path $file) {
        $content = Get-Content -Path $file -Raw
        $content = $content -replace '<Sentry/([^>]+)>', '"$1"'
        Set-Content -Path $file -Value $content
    } else {
        Write-Host "File not found: $file"
    }
}
$privateHeaderFile = "$CocoaSdkPath/PrivateHeaders/PrivatesHeader.h"
if (Test-Path $privateHeaderFile) {
    $content = Get-Content -Path $privateHeaderFile -Raw
    $content = $content -replace '"SentryDefines.h"', '"../Headers/SentryDefines.h"'
    $content = $content -replace '"SentryProfilingConditionals.h"', '"../Headers/SentryProfilingConditionals.h"'
    Set-Content -Path $privateHeaderFile -Value $content
    Write-Host "Patched includes: $privateHeaderFile"
} else {
    Write-Host "File not found: $privateHeaderFile"
}

# Generate bindings
Write-Output 'Generating bindings with Objective Sharpie.'
sharpie bind -sdk $iPhoneSdkVersion `
    -scope "$CocoaSdkPath" `
    "$CocoaSdkPath/Headers/Sentry.h" `
    "$CocoaSdkPath/PrivateHeaders/PrivateSentrySDKOnly.h" `
    -o $BindingsPath `
    -c -Wno-objc-property-no-attribute

# Ensure backup path exists
if (!(Test-Path $BackupPath))
{
    New-Item -ItemType Directory -Path $BackupPath | Out-Null
}

# The following header will be added to patched files.  The notice applies
# to those files, not this script which generates the files.
$Header = @"
// -----------------------------------------------------------------------------
// This file is auto-generated by Objective Sharpie and patched via the script
// at /scripts/generate-cocoa-bindings.ps1.  Do not edit this file directly.
// If changes are required, update the script instead.
// -----------------------------------------------------------------------------
"@

################################################################################
# Patch StructsAndEnums.cs
################################################################################
$File = 'StructsAndEnums.cs'
Write-Output "Patching $BindingsPath/$File"
Copy-Item "$BindingsPath/$File" -Destination "$BackupPath/$File"
$Text = Get-Content "$BindingsPath/$File" -Raw

# Tabs to spaces
$Text = $Text -replace '\t', '    '

# Trim extra newline at EOF
$Text = $Text -replace '\n$', ''

# Insert namespace
$Text = $Text -replace 'using .+;\n\n', "$&namespace Sentry.CocoaSdk;`n`n"

# Public to internal
$Text = $Text -replace '\bpublic\b', 'internal'

# Remove static CFunctions class
$Text = $Text -replace '(?ms)\nstatic class CFunctions.*?}\n', ''

# This enum resides in the Sentry-Swift.h
# Appending it here so we don't need to import and create bindings for the entire header
$SentryLevel = @'

[Native]
internal enum SentryLevel : ulong
{
    None = 0,
    Debug = 1,
    Info = 2,
    Warning = 3,
    Error = 4,
    Fatal = 5
}
'@

# This enum resides in the Sentry-Swift.h
# Appending it here so we don't need to import and create bindings for the entire header
$SentryTransactionNameSource = @'

[Native]
internal enum SentryTransactionNameSource : long
{
    Custom = 0,
    Url = 1,
    Route = 2,
    View = 3,
    Component = 4,
    Task = 5
}
'@

# This enum resides in the Sentry-Swift.h
# Appending it here so we don't need to import and create bindings for the entire header
$SentryReplayQuality = @'

[Native]
internal enum SentryReplayQuality : long
{
    Low = 0,
    Medium = 1,
    High = 2
}
'@

# This enum resides in the Sentry-Swift.h
# Appending it here so we don't need to import and create bindings for the entire header
$SentryReplayType = @'

[Native]
internal enum SentryReplayType : long
{
    Session = 0,
    Buffer = 1
}
'@

# This enum resides in the Sentry-Swift.h
# Appending it here so we don't need to import and create bindings for the entire header
$SentryRRWebEventType = @'

[Native]
internal enum SentryRRWebEventType : long
{
    None = 0,
    Touch = 3,
    Meta = 4,
    Custom = 5
}
'@

$Text += "`n$SentryLevel"
$Text += "`n$SentryTransactionNameSource"
$Text += "`n$SentryReplayQuality"
$Text += "`n$SentryReplayType"
$Text += "`n$SentryRRWebEventType"



# Add header and output file
$Text = "$Header`n`n$Text"
$Text | Out-File "$BindingsPath/$File"

################################################################################
# Patch ApiDefinitions.cs
################################################################################
$File = 'ApiDefinitions.cs'
Write-Output "Patching $BindingsPath/$File"
Copy-Item "$BindingsPath/$File" -Destination "$BackupPath/$File"
$Text = Get-Content "$BindingsPath/$File" -Raw

# Tabs to spaces
$Text = $Text -replace '\t', '    '

# Trim extra newline at EOF
$Text = $Text -replace '\n$', ''

# Insert namespace
$Text = $Text -replace 'using .+;\n\n', "$&namespace Sentry.CocoaSdk;`n`n"

# Set Internal attributes on interfaces and delegates
$Text = $Text -replace '(?m)^(partial interface|interface|delegate)\b', "[Internal]`n$&"

# Fix ISentrySerializable usage
$Text = $Text -replace '\bISentrySerializable\b', 'SentrySerializable'

# Remove INSCopying due to https://github.com/xamarin/xamarin-macios/issues/17130
$Text = $Text -replace ': INSCopying,', ':' -replace '\s?[:,] INSCopying', ''

# Fix delegate argument names
$Text = $Text -replace '(NSError) arg\d', '$1 error'
$Text = $Text -replace '(NSHttpUrlResponse) arg\d', '$1 response'
$Text = $Text -replace '(SentryEvent) arg\d', '$1 @event'
$Text = $Text -replace '(SentrySamplingContext) arg\d', '$1 samplingContext'
$Text = $Text -replace '(SentryBreadcrumb) arg\d', '$1 breadcrumb'
$Text = $Text -replace '(SentrySpan) arg\d', '$1 span'
$Text = $Text -replace '(SentryAppStartMeasurement) arg\d', '$1 appStartMeasurement'

# Adjust nullable return delegates (though broken until this is fixed: https://github.com/xamarin/xamarin-macios/issues/17109)
$Text = $Text -replace 'delegate \w+ Sentry(BeforeBreadcrumb|BeforeSendEvent|TracesSampler)Callback', "[return: NullAllowed]`n$&"

# Adjust protocols (some are models)
$Text = $Text -replace '(?ms)(@protocol.+?)/\*.+?\*/', '$1'
$Text = $Text -replace '(?ms)@protocol (SentrySerializable|SentrySpan).+?\[Protocol\]', "`$&`n[Model]"

# Adjust SentrySpan base type
$Text = $Text -replace 'interface SentrySpan\b', "[BaseType (typeof(NSObject))]`n`$&"

# Fix string constants
$Text = $Text -replace '(?m)(.*\n){2}^\s{4}NSString k.+?\n\n?', ''
$Text = $Text -replace '(?m)(.*\n){4}^partial interface Constants\n{\n}\n', ''
$Text = $Text -replace '\[Verify \(ConstantsInterfaceAssociation\)\]\n', ''

# Remove SentryVersionNumber
$Text = $Text -replace '.*SentryVersionNumber.*\n?', ''

# Remove SentryVersionString
$Text = $Text -replace '.*SentryVersionString.*\n?', ''

# Remove duplicate attributes
$s = 'partial interface Constants'
$t = $Text -split $s, 2
$t[1] = $t[1] -replace "\[Static\]\n\[Internal\]\n$s", $s
$Text = $t -join $s

# Remove empty Constants block
$Text = $Text -replace '\[Static\]\s*\[Internal\]\s*partial\s+interface\s+Constants\s\{[\s\n]*\}\n\n', ''

# Update MethodToProperty translations
$Text = $Text -replace '(Export \("get\w+"\)\]\n)\s*\[Verify \(MethodToProperty\)\]\n(.+ \{ get; \})', '$1$2'
$Text = $Text -replace '\[Verify \(MethodToProperty\)\]\n\s*(.+ (?:Hash|Value|DefaultIntegrations) \{ get; \})', '$1'
$Text = $Text -replace '\[Verify \(MethodToProperty\)\]\n\s*(.+) \{ get; \}', '$1();'

# Allow weakly typed NSArray
# We have some that accept either NSString or NSRegularExpression, which have no common type so they use NSObject
$Text = $Text -replace '\s*\[Verify \(StronglyTypedNSArray\)\]\n', ''

# Fix broken line comment
$Text = $Text -replace '(DEPRECATED_MSG_ATTRIBUTE\()\n\s*', '$1'

# Remove default IsEqual implementation (already implemented by NSObject)
$Text = $Text -replace '(?ms)\n?^ *// [^\n]*isEqual:.*?$.*?;\n', ''

# Replace obsolete platform availability attributes
$Text = $Text -replace '([\[,] )MacCatalyst \(', '$1Introduced (PlatformName.MacCatalyst, '
$Text = $Text -replace '([\[,] )Mac \(', '$1Introduced (PlatformName.MacOSX, '
$Text = $Text -replace '([\[,] )iOS \(', '$1Introduced (PlatformName.iOS, '

# Make interface partial if we need to access private APIs.  Other parts will be defined in PrivateApiDefinitions.cs
$Text = $Text -replace '(?m)^interface SentryScope', 'partial $&'

# Prefix SentryBreadcrumb.Serialize and SentryScope.Serialize with new (since these hide the base method)
$Text = $Text -replace '(?m)(^\s*\/\/[^\r\n]*$\s*\[Export \("serialize"\)\]$\s*)(NSDictionary)', '${1}new $2'

$Text = $Text -replace '.*SentryEnvelope .*?[\s\S]*?\n\n', ''
$Text = $Text -replace '.*typedef.*SentryOnAppStartMeasurementAvailable.*?[\s\S]*?\n\n', ''
#$Text = $Text -replace '\n.*SentryReplayBreadcrumbConverter.*?[\s\S]*?\);\n', ''

$propertiesToRemove = @(
    'SentryAppStartMeasurement',
    'SentryOnAppStartMeasurementAvailable',
    'SentryMetricsAPI',
    'SentryExperimentalOptions',
    'description',
    'enableMetricKitRawPayload'
)

foreach ($property in $propertiesToRemove) {
    $Text = $Text -replace "\n.*property.*$property.*?[\s\S]*?\}\n", ''
}

# This interface resides in the Sentry-Swift.h
# Appending it here so we don't need to import and create bindings for the entire header
$SentryId = @'

// @interface SentryId : NSObject
[BaseType (typeof(NSObject), Name = "_TtC6Sentry8SentryId")]
[Internal]
interface SentryId
{
    // @property (nonatomic, strong, class) SentryId * _Nonnull empty;
    [Static]
    [Export ("empty", ArgumentSemantic.Strong)]
    SentryId Empty { get; set; }

    // @property (readonly, copy, nonatomic) NSString * _Nonnull sentryIdString;
    [Export ("sentryIdString")]
    string SentryIdString { get; }

    // -(instancetype _Nonnull)initWithUuid:(NSUUID * _Nonnull)uuid __attribute__((objc_designated_initializer));
    [Export ("initWithUuid:")]
    [DesignatedInitializer]
    NativeHandle Constructor (NSUuid uuid);

    // -(instancetype _Nonnull)initWithUUIDString:(NSString * _Nonnull)uuidString __attribute__((objc_designated_initializer));
    [Export ("initWithUUIDString:")]
    [DesignatedInitializer]
    NativeHandle Constructor (string uuidString);

    // @property (readonly, nonatomic) NSUInteger hash;
    [Export ("hash")]
    nuint Hash { get; }
}
'@

$Text += "`n$SentryId"

# This interface resides in the Sentry-Swift.h
# Appending it here so we don't need to import and create bindings for the entire header
$SentryReplayOptions = @'

// @interface SentryReplayOptions : NSObject <SentryRedactOptions>
[BaseType (typeof(NSObject), Name = "_TtC6Sentry19SentryReplayOptions")]
[Internal]
interface SentryReplayOptions //: ISentryRedactOptions
{
    // @property (nonatomic) float sessionSampleRate;
    [Export ("sessionSampleRate")]
    float SessionSampleRate { get; set; }

    // @property (nonatomic) float onErrorSampleRate;
    [Export ("onErrorSampleRate")]
    float OnErrorSampleRate { get; set; }

    // @property (nonatomic) BOOL maskAllText;
    [Export ("maskAllText")]
    bool MaskAllText { get; set; }

    // @property (nonatomic) BOOL maskAllImages;
    [Export ("maskAllImages")]
    bool MaskAllImages { get; set; }

    // @property (nonatomic) enum SentryReplayQuality quality;
    [Export ("quality", ArgumentSemantic.Assign)]
    SentryReplayQuality Quality { get; set; }

    /*

    // @property (copy, nonatomic) NSArray<Class> * _Nonnull maskedViewClasses;
    //[Export ("maskedViewClasses", ArgumentSemantic.Copy)]
    //Class[] MaskedViewClasses { get; set; }

    // @property (copy, nonatomic) NSArray<Class> * _Nonnull unmaskedViewClasses;
    //[Export ("unmaskedViewClasses", ArgumentSemantic.Copy)]
    //Class[] UnmaskedViewClasses { get; set; }

    // @property (readonly, nonatomic) NSInteger replayBitRate;
    [Export ("replayBitRate")]
    nint ReplayBitRate { get; }

    // @property (readonly, nonatomic) float sizeScale;
    [Export ("sizeScale")]
    float SizeScale { get; }

    // @property (nonatomic) NSUInteger frameRate;
    [Export ("frameRate")]
    nuint FrameRate { get; set; }

    // @property (readonly, nonatomic) NSTimeInterval errorReplayDuration;
    [Export ("errorReplayDuration")]
    double ErrorReplayDuration { get; }

    // @property (readonly, nonatomic) NSTimeInterval sessionSegmentDuration;
    [Export ("sessionSegmentDuration")]
    double SessionSegmentDuration { get; }

    // @property (readonly, nonatomic) NSTimeInterval maximumDuration;
    [Export ("maximumDuration")]
    double MaximumDuration { get; }

    // -(instancetype _Nonnull)initWithSessionSampleRate:(float)sessionSampleRate onErrorSampleRate:(float)onErrorSampleRate maskAllText:(BOOL)maskAllText maskAllImages:(BOOL)maskAllImages __attribute__((objc_designated_initializer));
    [Export ("initWithSessionSampleRate:onErrorSampleRate:maskAllText:maskAllImages:")]
    [DesignatedInitializer]
    NativeHandle Constructor (float sessionSampleRate, float onErrorSampleRate, bool maskAllText, bool maskAllImages);

    // -(instancetype _Nonnull)initWithDictionary:(NSDictionary<NSString *,id> * _Nonnull)dictionary;
    [Export ("initWithDictionary:")]
    NativeHandle Constructor (NSDictionary<NSString, NSObject> dictionary);
    */
}
'@

$Text += "`n$SentryReplayOptions"

# This interface resides in the Sentry-Swift.h
# Appending it here so we don't need to import and create bindings for the entire header
$SentryRRWebEvent = @'

// @interface SentryRRWebEvent : NSObject <SentryRRWebEvent>
[BaseType (typeof(NSObject), Name = "_TtC6Sentry16SentryRRWebEvent")]
[Protocol]
[Model]
[DisableDefaultCtor]
[Internal]
interface SentryRRWebEvent : SentrySerializable
{
	// @property (readonly, nonatomic) enum SentryRRWebEventType type;
	[Export ("type")]
	SentryRRWebEventType Type { get; }

	// @property (readonly, copy, nonatomic) NSDate * _Nonnull timestamp;
	[Export ("timestamp", ArgumentSemantic.Copy)]
	NSDate Timestamp { get; }

	// @property (readonly, copy, nonatomic) NSDictionary<NSString *,id> * _Nullable data;
	[NullAllowed, Export ("data", ArgumentSemantic.Copy)]
	NSDictionary<NSString, NSObject> Data { get; }

	// -(instancetype _Nonnull)initWithType:(enum SentryRRWebEventType)type timestamp:(NSDate * _Nonnull)timestamp data:(NSDictionary<NSString *,id> * _Nullable)data __attribute__((objc_designated_initializer));
	[Export ("initWithType:timestamp:data:")]
	[DesignatedInitializer]
	NativeHandle Constructor (SentryRRWebEventType type, NSDate timestamp, [NullAllowed] NSDictionary<NSString, NSObject> data);

	// -(NSDictionary<NSString *,id> * _Nonnull)serialize __attribute__((warn_unused_result("")));
	[Export ("serialize")]
	new NSDictionary<NSString, NSObject> Serialize();
}
'@

$Text += "`n$SentryRRWebEvent"

# This interface resides in the Sentry-Swift.h
# Appending it here so we don't need to import and create bindings for the entire header
$SentryReplayBreadcrumbConverter = @'

// @protocol SentryReplayBreadcrumbConverter <NSObject>
[Protocol (Name = "_TtP6Sentry31SentryReplayBreadcrumbConverter_")]
[BaseType (typeof(NSObject), Name = "_TtP6Sentry31SentryReplayBreadcrumbConverter_")]
[Model]
[Internal]
interface SentryReplayBreadcrumbConverter
{
	// @required -(id<SentryRRWebEvent> _Nullable)convertFrom:(SentryBreadcrumb * _Nonnull)breadcrumb __attribute__((warn_unused_result("")));
	[Abstract]
	[Export ("convertFrom:")]
	[return: NullAllowed]
	SentryRRWebEvent ConvertFrom (SentryBreadcrumb breadcrumb);
}
'@

$Text += "`n$SentryReplayBreadcrumbConverter"

# This interface resides in the Sentry-Swift.h
# Appending it here so we don't need to import and create bindings for the entire header
$SentryViewScreenshotProvider = @'

// @protocol SentryViewScreenshotProvider <NSObject>
[Protocol (Name = "_TtP6Sentry28SentryViewScreenshotProvider_")]
[Model]
[BaseType (typeof(NSObject), Name = "_TtP6Sentry28SentryViewScreenshotProvider_")]
[Internal]
interface SentryViewScreenshotProvider
{
	// @required -(void)imageWithView:(UIView * _Nonnull)view onComplete:(void (^ _Nonnull)(UIImage * _Nonnull))onComplete;
	[Abstract]
	[Export ("imageWithView:onComplete:")]
	void OnComplete (UIView view, Action<UIImage> onComplete);
}
'@

$Text += "`n$SentryViewScreenshotProvider"

# This interface resides in the Sentry-Swift.h
# Appending it here so we don't need to import and create bindings for the entire header
$defaultReplayBreadcrumbConverter = @'

// @interface SentrySRDefaultBreadcrumbConverter : NSObject <SentryReplayBreadcrumbConverter>
[BaseType (typeof(NSObject), Name = "_TtC6Sentry34SentrySRDefaultBreadcrumbConverter")]
[Internal]
interface SentrySRDefaultBreadcrumbConverter
{
	// -(id<SentryRRWebEvent> _Nullable)convertFrom:(SentryBreadcrumb * _Nonnull)breadcrumb __attribute__((warn_unused_result("")));
	[Export ("convertFrom:")]
	[return: NullAllowed]
	SentryRRWebEvent ConvertFrom (SentryBreadcrumb breadcrumb);
}
'@

$Text += "`n$defaultReplayBreadcrumbConverter"

# This interface resides in the Sentry-Swift.h
# Appending it here so we don't need to import and create bindings for the entire header
$sentrySessionReplayIntegration = @'

// @interface SentrySessionReplayIntegration : SentryBaseIntegration
[BaseType (typeof(NSObject))]
[Internal]
interface SentrySessionReplayIntegration
{
    // -(instancetype _Nonnull)initForManualUse:(SentryOptions * _Nonnull)options;
    [Export ("initForManualUse:")]
    NativeHandle Constructor (SentryOptions options);

    // -(BOOL)captureReplay;
    [Export ("captureReplay")]
    bool CaptureReplay();

    // -(void)configureReplayWith:(id<SentryReplayBreadcrumbConverter> _Nullable)breadcrumbConverter screenshotProvider:(id<SentryViewScreenshotProvider> _Nullable)screenshotProvider;
    [Export ("configureReplayWith:screenshotProvider:")]
    void ConfigureReplayWith ([NullAllowed] SentryReplayBreadcrumbConverter breadcrumbConverter, [NullAllowed] SentryViewScreenshotProvider screenshotProvider);

    // -(void)pause;
    [Export ("pause")]
    void Pause ();

    // -(void)resume;
    [Export ("resume")]
    void Resume ();

    // -(void)stop;
    [Export ("stop")]
    void Stop ();

    // -(void)start;
    [Export ("start")]
    void Start ();

    // +(id<SentryRRWebEvent> _Nonnull)createBreadcrumbwithTimestamp:(NSDate * _Nonnull)timestamp category:(NSString * _Nonnull)category message:(NSString * _Nullable)message level:(enum SentryLevel)level data:(NSDictionary<NSString *,id> * _Nullable)data;
    [Static]
    [Export ("createBreadcrumbwithTimestamp:category:message:level:data:")]
    SentryRRWebEvent CreateBreadcrumbwithTimestamp (NSDate timestamp, string category, [NullAllowed] string message, SentryLevel level, [NullAllowed] NSDictionary<NSString, NSObject> data);

    // +(id<SentryRRWebEvent> _Nonnull)createNetworkBreadcrumbWithTimestamp:(NSDate * _Nonnull)timestamp endTimestamp:(NSDate * _Nonnull)endTimestamp operation:(NSString * _Nonnull)operation description:(NSString * _Nonnull)description data:(NSDictionary<NSString *,id> * _Nonnull)data;
    [Static]
    [Export ("createNetworkBreadcrumbWithTimestamp:endTimestamp:operation:description:data:")]
    SentryRRWebEvent CreateNetworkBreadcrumbWithTimestamp (NSDate timestamp, NSDate endTimestamp, string operation, string description, NSDictionary<NSString, NSObject> data);

    // +(id<SentryReplayBreadcrumbConverter> _Nonnull)createDefaultBreadcrumbConverter;
    [Static]
    [Export ("createDefaultBreadcrumbConverter")]
    SentryReplayBreadcrumbConverter CreateDefaultBreadcrumbConverter();
}
'@

$Text += "`n$sentrySessionReplayIntegration"

# Add header and output file
$Text = "$Header`n`n$Text"
$Text | Out-File "$BindingsPath/$File"
