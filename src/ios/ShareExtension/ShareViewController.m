//
//  ShareViewController.m
//  OpenWith - Share Extension
//

//
// The MIT License (MIT)
//
// Copyright (c) 2017 Jean-Christophe Hoelt
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import <UIKit/UIKit.h>
#import <Social/Social.h>
#import "ShareViewController.h"
#import <MobileCoreServices/MobileCoreServices.h>


@interface ShareViewController : SLComposeServiceViewController {
    int _verbosityLevel;
    NSUserDefaults *_userDefaults;
    NSString *_backURL;
}
@property (nonatomic) int verbosityLevel;
@property (nonatomic,retain) NSUserDefaults *userDefaults;
@property (nonatomic,retain) NSString *backURL;
@end

/*
 * Constants
 */

#define VERBOSITY_DEBUG  0
#define VERBOSITY_INFO  10
#define VERBOSITY_WARN  20
#define VERBOSITY_ERROR 30

@implementation ShareViewController

@synthesize verbosityLevel = _verbosityLevel;
@synthesize userDefaults = _userDefaults;
@synthesize backURL = _backURL;

- (void) log:(int)level message:(NSString*)message {
    if (level >= self.verbosityLevel) {
        NSLog(@"[ShareViewController.m]%@", message);
    }
}
- (void) debug:(NSString*)message { [self log:VERBOSITY_DEBUG message:message]; }
- (void) info:(NSString*)message { [self log:VERBOSITY_INFO message:message]; }
- (void) warn:(NSString*)message { [self log:VERBOSITY_WARN message:message]; }
- (void) error:(NSString*)message { [self log:VERBOSITY_ERROR message:message]; }

- (void) setup {
    self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:SHAREEXT_GROUP_IDENTIFIER];
    self.verbosityLevel = [self.userDefaults integerForKey:@"verbosityLevel"];
    [self debug:@"[setup]"];
}

- (BOOL) isContentValid {
    return YES;
}

- (void) openURL:(nonnull NSURL *)url {

    SEL selector = NSSelectorFromString(@"openURL:options:completionHandler:");

    UIResponder* responder = self;
    while ((responder = [responder nextResponder]) != nil) {
        NSLog(@"responder = %@", responder);
        if([responder respondsToSelector:selector] == true) {
            NSMethodSignature *methodSignature = [responder methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];

            // Arguments
            void (^completion)(BOOL success) = ^void(BOOL success) {
                NSLog(@"Completions block: %i", success);
            };
            if (@available(iOS 13.0, *)) {
                UISceneOpenExternalURLOptions * options = [[UISceneOpenExternalURLOptions alloc] init];
                options.universalLinksOnly = false;
                
                [invocation setTarget: responder];
                [invocation setSelector: selector];
                [invocation setArgument: &url atIndex: 2];
                [invocation setArgument: &options atIndex:3];
                [invocation setArgument: &completion atIndex: 4];
                [invocation invoke];
                break;
            } else {
                NSDictionary<NSString *, id> *options = [NSDictionary dictionary];
                
                [invocation setTarget: responder];
                [invocation setSelector: selector];
                [invocation setArgument: &url atIndex: 2];
                [invocation setArgument: &options atIndex:3];
                [invocation setArgument: &completion atIndex: 4];
                [invocation invoke];
                break;
            }
        }
    }
}

- (void) didSelectPost {

    [self setup];
    [self debug:@"[didSelectPost]"];
    
    for (NSItemProvider* itemProvider in ((NSExtensionItem*)self.extensionContext.inputItems[0]).attachments) {
        [self debug:[NSString stringWithFormat:@"item provider registered indentifiers = %@", itemProvider.registeredTypeIdentifiers]];

        // TEXT case
        if ([itemProvider hasItemConformingToTypeIdentifier:@"public.text"]) {
            [itemProvider loadItemForTypeIdentifier:@"public.text" options:nil completionHandler: ^(NSString* item, NSError *error) {
                [self debug:[NSString stringWithFormat:@"public.text  = %@", item]];
                NSString *uti = @"public.plain-text";
                NSDictionary *dict = @{
                    @"text" : self.contentText,
                    @"data" : item,
                    @"uti": uti,
                    @"utis": itemProvider.registeredTypeIdentifiers,
                    @"name": @"",
                    @"type": [self mimeTypeFromUti:uti],
                };
                
                [self.userDefaults setObject:dict forKey:@"share"];
                [self.userDefaults synchronize];

                NSString *url = [NSString stringWithFormat:@"%@://share", SHAREEXT_URL_SCHEME];

                [self openURL:[NSURL URLWithString:url]];

                [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
            }];
        }

        // IMAGE case
        else if ([itemProvider hasItemConformingToTypeIdentifier:@"public.image"]) {
            [itemProvider loadItemForTypeIdentifier:@"public.image" options:nil completionHandler: ^(NSURL *item, NSError *error) {
                if (item != nil) {
                    NSString *imageName = [[item path] lastPathComponent];
                    
                    BOOL success;
                    NSError *error;

                    NSFileManager *fileManager = [NSFileManager defaultManager];
                    
                    NSString *groupContainerURL = [NSString stringWithString:[fileManager containerURLForSecurityApplicationGroupIdentifier:@"group.ch.ofsoftware.ofbau.shareextension"].path];

                    NSString *filePath = [groupContainerURL stringByAppendingPathComponent:imageName];
                    NSString *src = item.path;
                    
                    [self debug:[NSString stringWithFormat:@"%@", filePath]];
                    [self debug:[NSString stringWithFormat:@"%@", src]];

                    success = [fileManager fileExistsAtPath:src];
                    if (success) {
                        success = [fileManager fileExistsAtPath:filePath];
                        if (success) {
                            [fileManager removeItemAtPath:filePath error:&error];
                        }
                        
                        success = [fileManager copyItemAtPath:src toPath:filePath error:&error];
                        
                        [self debug:[NSString stringWithFormat:@"%@", error]];
                        
                        if (success) {
                            [self debug:[NSString stringWithFormat:@"%@", @"copy successful"]];
                        }
                    }
                    
                    [self debug:[NSString stringWithFormat:@"public.image  = %@", item]];
                                        NSString *uti = @"public.image";
                                        NSDictionary *dict = @{
                                            @"text" : self.contentText,
                                            @"data" : filePath,
                                            @"uti": uti,
                                            @"utis": itemProvider.registeredTypeIdentifiers,
                                            @"name": imageName,
                                            @"type": [self mimeTypeFromUti:uti],
                                        };
                    
                    [self.userDefaults setObject:dict forKey:@"share"];
                    [self.userDefaults synchronize];

                    NSString *url = [NSString stringWithFormat:@"%@://share", SHAREEXT_URL_SCHEME];

                    [self openURL:[NSURL URLWithString:url]];
                    
                    [NSThread sleepForTimeInterval:10.0f];

                    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
                }
            }];
        }

        // Other files
        else {
            __block NSString *uti = itemProvider.registeredTypeIdentifiers[0];
            [itemProvider loadItemForTypeIdentifier:uti options:nil completionHandler: ^(id<NSSecureCoding> item, NSError *error) {

                [self debug:[NSString stringWithFormat:@"%@", (__bridge CFStringRef _Nonnull)uti]];
                
                NSString *baseUti = nil;
                if (
                    UTTypeConformsTo((__bridge CFStringRef _Nonnull)uti, kUTTypeAudiovisualContent)
                    ) {
                    baseUti = @"public.audiovisual-content";
                    // @todo: make resize
                }
                else if ( UTTypeConformsTo((__bridge CFStringRef _Nonnull)uti,kUTTypeAudio)) {
                    baseUti = @"public.audio";
                }
                else if ( UTTypeConformsTo((__bridge CFStringRef _Nonnull)uti,kUTTypeURL)) {
                    baseUti = @"public.url";
                }
                else if ( UTTypeConformsTo((__bridge CFStringRef _Nonnull)uti,kUTTypeFileURL)) {
                    baseUti = @"public.file-url";
                }
                else {
                    baseUti = uti;
                }
                [self debug:[NSString stringWithFormat:@"%@ = %@", baseUti, item]];

                __block NSURL *fileUrl = item;
                
                [self debug:[NSString stringWithFormat:@"%@", fileUrl]];
                
                NSString *suggestedName = fileUrl.lastPathComponent;
                
                BOOL success;

                NSFileManager *fileManager = [NSFileManager defaultManager];
                
                NSString *groupContainerURL = [NSString stringWithString:[fileManager containerURLForSecurityApplicationGroupIdentifier:@"group.ch.ofsoftware.ofbau.shareextension"].path];

                NSString *filePath = [groupContainerURL stringByAppendingPathComponent:suggestedName];
                NSString *src = fileUrl.path;
                
                [self debug:[NSString stringWithFormat:@"%@", filePath]];
                [self debug:[NSString stringWithFormat:@"%@", src]];

                success = [fileManager fileExistsAtPath:src];
                if (success) {
                    success = [fileManager fileExistsAtPath:filePath];
                    if (success) {
                        [fileManager removeItemAtPath:filePath error:&error];
                    }
                    
                    success = [fileManager copyItemAtPath:src toPath:filePath error:&error];
                    
                    [self debug:[NSString stringWithFormat:@"%@", error]];
                    
                    if (success) {
                        [self debug:[NSString stringWithFormat:@"%@", @"copy successful"]];
                    }
                }

                if (fileUrl != nil) {
                    [self debug:[NSString stringWithFormat:@"%@", suggestedName]];
                    
                    NSDictionary *dict = @{
                        @"text" : self.contentText,
                        @"data" : filePath,
                        @"uti"  : baseUti,
                        @"utis" : itemProvider.registeredTypeIdentifiers,
                        @"name" : suggestedName,
                        @"type" : [self mimeTypeFromUti:uti],
                    };
                                            
                    [self.userDefaults setObject:dict forKey:@"share"];
                    [self.userDefaults synchronize];

                    NSString *url = [NSString stringWithFormat:@"%@://share", SHAREEXT_URL_SCHEME];

                    [self openURL:[NSURL URLWithString:url]];

                    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
                }
            }];
        }
    }
}

- (NSArray*) configurationItems {
    // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
    return @[];
}

- (NSString*) backURLFromBundleID: (NSString*)bundleId {
    if (bundleId == nil) return nil;
    // App Store - com.apple.AppStore
    if ([bundleId isEqualToString:@"com.apple.AppStore"]) return @"itms-apps://";
    // Calculator - com.apple.calculator
    // Calendar - com.apple.mobilecal
    // Camera - com.apple.camera
    // Clock - com.apple.mobiletimer
    // Compass - com.apple.compass
    // Contacts - com.apple.MobileAddressBook
    // FaceTime - com.apple.facetime
    // Find Friends - com.apple.mobileme.fmf1
    // Find iPhone - com.apple.mobileme.fmip1
    // Game Center - com.apple.gamecenter
    // Health - com.apple.Health
    // iBooks - com.apple.iBooks
    // iTunes Store - com.apple.MobileStore
    // Mail - com.apple.mobilemail - message://
    if ([bundleId isEqualToString:@"com.apple.mobilemail"]) return @"message://";
    // Maps - com.apple.Maps - maps://
    if ([bundleId isEqualToString:@"com.apple.Maps"]) return @"maps://";
    // Messages - com.apple.MobileSMS
    // Music - com.apple.Music
    // News - com.apple.news - applenews://
    if ([bundleId isEqualToString:@"com.apple.news"]) return @"applenews://";
    // Notes - com.apple.mobilenotes - mobilenotes://
    if ([bundleId isEqualToString:@"com.apple.mobilenotes"]) return @"mobilenotes://";
    // Phone - com.apple.mobilephone
    // Photos - com.apple.mobileslideshow
    if ([bundleId isEqualToString:@"com.apple.mobileslideshow"]) return @"photos-redirect://";
    // Podcasts - com.apple.podcasts
    // Reminders - com.apple.reminders - x-apple-reminder://
    if ([bundleId isEqualToString:@"com.apple.reminders"]) return @"x-apple-reminder://";
    // Safari - com.apple.mobilesafari
    // Settings - com.apple.Preferences
    // Stocks - com.apple.stocks
    // Tips - com.apple.tips
    // Videos - com.apple.videos - videos://
    if ([bundleId isEqualToString:@"com.apple.videos"]) return @"videos://";
    // Voice Memos - com.apple.VoiceMemos - voicememos://
    if ([bundleId isEqualToString:@"com.apple.VoiceMemos"]) return @"voicememos://";
    // Wallet - com.apple.Passbook
    // Watch - com.apple.Bridge
    // Weather - com.apple.weather
    return @"";
}

// This is called at the point where the Post dialog is about to be shown.
// We use it to store the _hostBundleID
- (void) willMoveToParentViewController: (UIViewController*)parent {
    NSString *hostBundleID = [parent valueForKey:(@"_hostBundleID")];
    self.backURL = [self backURLFromBundleID:hostBundleID];
}

- (NSString *)mimeTypeFromUti: (NSString*)uti {
    if (uti == nil) {
        return nil;
    }
    CFStringRef cret = UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)uti, kUTTagClassMIMEType);
    NSString *ret = (__bridge_transfer NSString *)cret;
    return ret == nil ? uti : ret;
}

@end
