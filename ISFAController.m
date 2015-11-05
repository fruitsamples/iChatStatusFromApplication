/*

File: ISFAController.m

Abstract: Watches for application switches and updates iChat status using the Scripting Bridge

Version: 1.0

Disclaimer: IMPORTANT:  This Apple software is supplied to you by 
Apple Inc. ("Apple") in consideration of your agreement to the
following terms, and your use, installation, modification or
redistribution of this Apple software constitutes acceptance of these
terms.  If you do not agree with these terms, please do not use,
install, modify or redistribute this Apple software.

In consideration of your agreement to abide by the following terms, and
subject to these terms, Apple grants you a personal, non-exclusive
license, under Apple's copyrights in this original Apple software (the
"Apple Software"), to use, reproduce, modify and redistribute the Apple
Software, with or without modifications, in source and/or binary forms;
provided that if you redistribute the Apple Software in its entirety and
without modifications, you must retain this notice and the following
text and disclaimers in all such redistributions of the Apple Software. 
Neither the name, trademarks, service marks or logos of Apple Inc. 
may be used to endorse or promote products derived from the Apple
Software without specific prior written permission from Apple.  Except
as expressly stated in this notice, no other rights or licenses, express
or implied, are granted by Apple herein, including but not limited to
any patent rights that may be infringed by your derivative works or by
other works in which the Apple Software may be incorporated.

The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

Copyright (C) 2007 Apple Inc. All Rights Reserved.

*/


#import "ISFAController.h"

@interface ISFAController (PRIVATE) 
- (void)applicationSwitched;
- (void)applicationLaunched:(NSNotification *)notification;
- (void)applicationTerminated:(NSNotification *)notification;
- (void)registerForAppSwitchNotificationFor:(NSDictionary *)application;
@end

@implementation ISFAController

- (void)applicationSwitched
{
    NSDictionary *applicationInfo = [[NSWorkspace sharedWorkspace] activeApplication];
    pid_t switchedPid = (pid_t)[[applicationInfo valueForKey:@"NSApplicationProcessIdentifier"] integerValue];
	
	// Don't do anything if we do not have new application in the front, or if we are in the
	// front ourselves.
    if(switchedPid != _currentPid && switchedPid != getpid()) {
	
		// Only update iChat's status if it's running, and if the current status
		// is set to available.
        if([_iChatApp isRunning]) {
        
            if ([_iChatApp status] == iChatMyStatusAvailable) {
                // Grab the icon of the running application and convert to a TIFF.
                NSImage *iconImage = [[NSWorkspace sharedWorkspace] iconForFile:[applicationInfo valueForKey:@"NSApplicationPath"]];
                NSData *tiffRepresentation = [iconImage TIFFRepresentation];
                
                // Set the buddy picture in iChat to the TIFF (using the bridged iChat application object).
                [_iChatApp setImage: tiffRepresentation];
                
                // Set the application's icon view  in our window to the icon image.
                [_appIconView setImage: iconImage];
                
				
                NSString *statusString = [NSString stringWithFormat:@"Using %@", [applicationInfo objectForKey:@"NSApplicationName"]];
                
                // Set the status message in iChat to the running application (using the bridged iChat application object).
                [_iChatApp setStatusMessage: statusString];
				
				// Set the status message in our window.
                [_appLabelField setStringValue: statusString];
            }
            else {
                [_appIconView setImage: nil];
                [_appLabelField setStringValue: @"Status is not set to available"];
            }
            
        }
        else {
            [_appIconView setImage: nil];
            [_appLabelField setStringValue: @"iChat is not running"];
        }

        NSLog(@"Application: %@", [applicationInfo objectForKey:@"NSApplicationName"]);
        _currentPid = switchedPid;
    }
}

- (void)applicationLaunched:(NSNotification *)notification
{
	// A new application has launched.  Make sure we get notifications when it activates.
    [self registerForAppSwitchNotificationFor:[notification userInfo]];
    [self applicationSwitched];
}

- (void)applicationTerminated:(NSNotification *)notification
{
    NSNumber *pidNumber = [[notification userInfo] valueForKey:@"NSApplicationProcessIdentifier"];
    AXObserverRef observer = (AXObserverRef)[_observers objectForKey:pidNumber];
    if(observer) {
        // Stop listening to the accessability notifications for the dead application.
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                              AXObserverGetRunLoopSource(observer),
                              kCFRunLoopDefaultMode);
        [_observers removeObjectForKey:pidNumber];
    } else {
        NSLog(@"Application \"%@\" that we didn't know about quit!", [[notification userInfo] valueForKey:@"NSApplicationName"]);
    }
}

static void applicationSwitched(AXObserverRef observer, AXUIElementRef element, CFStringRef notification, void *self)
{
    [(id)self applicationSwitched];
}

- (void)registerForAppSwitchNotificationFor:(NSDictionary *)application
{
    NSNumber *pidNumber = [application valueForKey:@"NSApplicationProcessIdentifier"];
    
	// If we're not watching for switch events for this application already
    if(![_observers objectForKey:pidNumber]) {
        pid_t pid = (pid_t)[pidNumber integerValue];
        // Create an Accessibility observer for the application
        AXObserverRef observer;
        if(AXObserverCreate(pid, applicationSwitched, &observer) == kAXErrorSuccess) {
            
            // Register for the application activated notification.
            CFRunLoopAddSource(CFRunLoopGetCurrent(),
                               AXObserverGetRunLoopSource(observer), 
                               kCFRunLoopDefaultMode);
            AXUIElementRef element = AXUIElementCreateApplication(pid);
            if(AXObserverAddNotification(observer, element, kAXApplicationActivatedNotification, self) != kAXErrorSuccess) {
                NSLog(@"Failed to create observer for application \"%@\".", [application valueForKey:@"NSApplicationName"]);
            } else {
                // Remember the observer so that we can deregister later.
                [_observers setObject:(id)observer forKey:pidNumber];
            }
            
            CFRelease(observer); // The observers dictionary wil hold on to the observer for us.
            CFRelease(element);  // We don't need the element any more.
        } else {
            NSLog(@"Failed to create observer for application \"%@\".", [application valueForKey:@"NSApplicationName"]);
        }  
    } else {
        NSLog(@"Attempted to observe application \"%@\" twice.", [application valueForKey:@"NSApplicationName"]);
    }
}

- (void)getiChatApp
{
    @try {
		// This will use the Scripting Bridge to get a reference to the main application class
		// for iChat, as defined in the iChat.h header (see ReadMe.txt for more information)
        _iChatApp = (iChatApplication *)[[[SBApplication classForApplicationWithBundleIdentifier:@"com.apple.iChat"] alloc] init];
    }
    @catch(NSException *except) {
        NSLog(@"Exception %@", except);
    }
}

- (void)awakeFromNib
{   
    [self getiChatApp];
    
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    _observers = [[NSMutableDictionary alloc] init];

    // Register for notification of app launch and termination so that we can register
    // and deregister foractivation notifications for them.
    [[workspace notificationCenter] addObserver:self 
                                       selector:@selector(applicationLaunched:) 
                                           name:NSWorkspaceDidLaunchApplicationNotification 
                                         object:workspace];
    [[workspace notificationCenter] addObserver:self 
                                       selector:@selector(applicationTerminated:) 
                                           name:NSWorkspaceDidTerminateApplicationNotification 
                                         object:workspace];
    
    // Register for activation notifications for all the currently running apps.
    for(NSDictionary *application in [workspace launchedApplications]) {
        [self registerForAppSwitchNotificationFor:application];
    }
    
    [self applicationSwitched];
}

- (void)dealloc
{
    // Stop listening to all the notifications.
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    for(NSNumber *pidNumber in _observers) {
        AXObserverRef observer = (AXObserverRef)[_observers objectForKey:pidNumber];
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                              AXObserverGetRunLoopSource(observer),
                              kCFRunLoopDefaultMode);
    }
    
    // This will also release the observers in the dictionary.
    [_observers release];
    
    [super dealloc];
}

- (IBAction) chatRoomButtonAction: (id) sender
{
	// Use Scripting Bridge bridged objects to make iChat join (or create)
	// an AIM chat room named @"ichatstatus".

    // Get the list of active services in iChat
    SBElementArray *services = [_iChatApp services];
    
    // We're looking for any AIM service
    iChatService *aimService = nil;
    
    // Iterate through the available services
    for (iChatService * svc in services) {
        // Use the first connected AIM service we have
        if (svc.serviceType == iChatServiceTypeAIM && svc.status == iChatConnectionStatusConnected) {
            aimService = svc;
            break;
        }
    }

    // if we did find an aim service, go to the chat room.
    if (aimService) {
        // Go to the chat room named "ichatstatus" on the AIM service we found.
        NSDictionary *chatProperties = [NSDictionary dictionaryWithObjectsAndKeys: aimService, @"service", 
                                                                                   @"ichatstatus", @"name", nil];

        // Get the class for the text chat AppleScript class
        Class textChatClass = [_iChatApp classForScriptingClass: @"text chat"];

        // Create the text chat object
        iChatTextChat *myChat = [[textChatClass alloc] initWithProperties: chatProperties];
        
        // Add the text chat to the app's list of open chats
        [[_iChatApp textChats] addObject: myChat];
        
        // iChat will now send out the request to create chat room (not synchronous)
    }
}

@end
