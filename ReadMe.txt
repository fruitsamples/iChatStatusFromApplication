iChatStatusFromApplication
v1.0

This application demonstrates the use of iChat's AppleScript API from Objective-C via the Scripting Bridge.

The application listens for frontmost-application change events using the Accessibility API, then sets the user's status message and icon to represent what application they're currently using.


The scripting bridge is a new feature in Mac OS X 10.5 that provides native Objective-C versions of AppleScript APIs.  It can also provide native Python and Ruby versions (though this is not demonstrated here).

The 'iChat.h' file contains an Objective-C header for the bridged version of iChat's Applescript API.  It was generated automatically by typing "sdef /Applications/iChat.app | sdp -fh --basename iChat" at the Terminal.


The application requires that "Enable access for assistive devices" is checked in the "Universal Access" System Preferences pane (this allows it to listen for active-application-changed events, it is not a requirement for using the Scripting Bridge).