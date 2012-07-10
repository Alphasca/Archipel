/*
 * TNWindowConnection.j
 *
 * Copyright (C) 2010 Antoine Mercadal <antoine.mercadal@inframonde.eu>
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

@import <Foundation/Foundation.j>

@import <AppKit/CPButton.j>
@import <AppKit/CPImageView.j>
@import <AppKit/CPTextField.j>

@import <StropheCappuccino/TNStropheStanza.j>

@import "../Model/TNDatasourceRoster.j"
@import "../Utils/EKShakeAnimation.j"
@import "../Views/TNModalWindow.j"
@import "../Views/TNSwitch.j"


TNConnectionControllerCurrentUserVCardRetreived = @"TNConnectionControllerCurrentUserVCardRetreived";
TNConnectionControllerConnectionStarted         = @"TNConnectionControllerConnectionStarted";

/*! @ingroup archipelcore
    subclass of CPWindow that allows to manage connection to XMPP Server
*/
@implementation TNConnectionController : CPObject
{
    @outlet CPButton        connectButton;
    @outlet CPImageView     spinning;
    @outlet CPTextField     boshService;
    @outlet CPTextField     JID;
    @outlet CPTextField     labelBoshService;
    @outlet CPTextField     labelJID;
    @outlet CPTextField     labelPassword;
    @outlet CPTextField     labelRemember;
    @outlet CPTextField     labelTitle;
    @outlet CPTextField     message;
    @outlet CPTextField     password;
    @outlet TNModalWindow   mainWindow              @accessors(readonly);
    @outlet TNSwitch        credentialRemember;

    BOOL                    _credentialRecovered    @accessors(getter=areCredentialRecovered);
    TNStropheStanza         _userVCard              @accessors(property=userVCard);

    CPDictionary            _credentialsHistory;
}

#pragma mark -
#pragma mark Initialization

/*! initialize the window when CIB is loaded
*/
- (void)awakeFromCib
{
    _credentialRecovered = NO;

    [mainWindow setShowsResizeIndicator:NO];
    [mainWindow setDefaultButton:connectButton];

    [password setSecure:YES];
    [password setNeedsLayout]; // for some reasons, with XCode 4, setSecure doesn't work every time. this force it to relayout

    [credentialRemember setTarget:self];
    [credentialRemember setAction:@selector(rememberCredentials:)];

    [labelTitle setStringValue:CPLocalizedString(@"Logon", @"Logon")];
    [labelTitle setTextShadowOffset:CPSizeMake(0.0, 1.0)];
    [labelTitle setValue:[CPColor whiteColor] forThemeAttribute:@"text-shadow-color" inState:CPThemeStateNormal];

    [labelJID setTextShadowOffset:CPSizeMake(0.0, 1.0)];
    [labelJID setValue:[CPColor whiteColor] forThemeAttribute:@"text-shadow-color" inState:CPThemeStateNormal];

    [labelPassword setTextShadowOffset:CPSizeMake(0.0, 1.0)];
    [labelPassword setValue:[CPColor whiteColor] forThemeAttribute:@"text-shadow-color" inState:CPThemeStateNormal];

    [labelBoshService setTextShadowOffset:CPSizeMake(0.0, 1.0)];
    [labelBoshService setValue:[CPColor whiteColor] forThemeAttribute:@"text-shadow-color" inState:CPThemeStateNormal];

    [labelRemember setTextShadowOffset:CPSizeMake(0.0, 1.0)];
    [labelRemember setValue:[CPColor whiteColor] forThemeAttribute:@"text-shadow-color" inState:CPThemeStateNormal];

    [message setTextShadowOffset:CPSizeMake(0.0, 1.0)];
    [message setValue:[CPColor whiteColor] forThemeAttribute:@"text-shadow-color" inState:CPThemeStateNormal];

    [labelTitle setTextColor:[CPColor colorWithHexString:@"000000"]];

    [connectButton setBezelStyle:CPRoundedBezelStyle];

    [[CPNotificationCenter defaultCenter] addObserver:self selector:@selector(_didJIDChange:) name:CPControlTextDidChangeNotification object:JID];
}


#pragma mark -
#pragma mark Notification handlers

- (void)_didReceiveUserVCard:(CPNotification)aNotification
{
    _userVCard = [[aNotification userInfo] firstChildWithName:@"vCard"];
    [[CPNotificationCenter defaultCenter] postNotificationName:TNConnectionControllerCurrentUserVCardRetreived object:self];
}

- (void)_didJIDChange:(CPNotification)aNotification
{
    if (_credentialsHistory && [_credentialsHistory containsKey:[JID stringValue]])
    {
        [password setStringValue:[[_credentialsHistory objectForKey:[JID stringValue]] objectForKey:@"password"] || @""];
        [boshService setStringValue:[[_credentialsHistory objectForKey:[JID stringValue]] objectForKey:@"service"] || @""];
        [credentialRemember setOn:YES animated:YES sendAction:NO];
    }
    else
    {
        var JIDObject;
        try { JIDObject = [TNStropheJID stropheJIDWithString:[JID stringValue]];} catch(e) {return;}

        [password setStringValue:@""];
        if ([JIDObject domain])
            [boshService setStringValue:@"http://" + [JIDObject domain] + @":5280/http-bind"];
        else
            [boshService setStringValue:@""];
        [credentialRemember setOn:NO animated:YES sendAction:NO];
    }
}


#pragma mark -
#pragma mark Utils

/*! Initialize credentials informations according to the Application Defaults
*/
- (void)initCredentials
{
    var defaults            = [CPUserDefaults standardUserDefaults],
        lastBoshService     = [defaults objectForKey:@"TNArchipelBOSHService"],
        lastJID             = [defaults objectForKey:@"TNArchipelBOSHJID"],
        lastPassword        = [defaults objectForKey:@"TNArchipelBOSHPassword"],
        lastRememberCred    = [defaults objectForKey:@"TNArchipelBOSHRememberCredentials"];

    _credentialsHistory     = [defaults objectForKey:@"TNArchipelBOSHCredentialHistory"] || [CPDictionary dictionary];

    if (lastBoshService)
        [boshService setStringValue:lastBoshService || @""];

    if (lastJID && lastJID != @"")
    {
        var JIDObject;
        try { JIDObject = [TNStropheJID stropheJIDWithString:lastJID] } catch(e){};
        [JID setStringValue:[JIDObject bare]];
    }

    [self _didJIDChange:nil];

    if ([credentialRemember isOn])
    {
        _credentialRecovered = YES;
        [password setStringValue:lastPassword || @""];
        [self connect:nil];
    }
}

/*! add History token
*/
- (void)saveCredentialsInHistory
{
    var historyToken = [CPDictionary dictionaryWithObjectsAndKeys:[password stringValue], @"password",
                                                                  [boshService stringValue], @"service"];

    [_credentialsHistory setObject:historyToken forKey:[JID stringValue]];
    [[CPUserDefaults standardUserDefaults] setObject:_credentialsHistory forKey:@"TNArchipelBOSHCredentialHistory"];
}

/*! add History token
*/
- (void)clearCredentialFromHistory
{
    [_credentialsHistory removeObjectForKey:[JID stringValue]];
    [[CPUserDefaults standardUserDefaults] setObject:_credentialsHistory forKey:@"TNArchipelBOSHCredentialHistory"];
}


#pragma mark -
#pragma mark Actions

/*! show the window
    @param sender the sender
*/
- (IBAction)showWindow:(id)sender
{
    [mainWindow center];
    [mainWindow makeKeyAndOrderFront:nil];
}

/*! hide the window
    @param sender the sender
*/
- (IBAction)hideWindow:(id)sender
{
    [mainWindow close];
}

/*! connection action
    @param sender the sender
*/
- (IBAction)connect:(id)sender
{
    var currentConnectionStatus = [[[TNStropheIMClient defaultClient] connection] currentStatus];

    if (currentConnectionStatus
        && currentConnectionStatus != Strophe.Status.DISCONNECTED
        && currentConnectionStatus != Strophe.Status.CONNFAIL
        && currentConnectionStatus != Strophe.Status.ERROR)
    {
        [[TNStropheIMClient defaultClient] disconnect];
        return;
    }

    var defaults = [CPUserDefaults standardUserDefaults];

    if ([credentialRemember isOn])
    {
        [self saveCredentialsInHistory];

        [defaults setObject:[JID stringValue] forKey:@"TNArchipelBOSHJID"];
        [defaults setObject:[password stringValue] forKey:@"TNArchipelBOSHPassword"];
        [defaults setObject:[boshService stringValue] forKey:@"TNArchipelBOSHService"];
        [defaults setBool:YES forKey:@"TNArchipelBOSHRememberCredentials"];
        _credentialRecovered = YES;
        CPLog.info("logging information saved");
    }
    else
    {
        _credentialRecovered = NO;
        [defaults setBool:NO forKey:@"TNArchipelLoginRememberCredentials"];
    }

    var connectionJID;

    try { connectionJID = [TNStropheJID stropheJIDWithString:[[JID stringValue] lowercaseString]]; } catch (e) {}

    if (![connectionJID domain])
    {
        [message setStringValue:CPLocalizedString(@"Full JID required", @"Full JID required")];
        return;
    }

    [connectionJID setResource:[defaults objectForKey:@"TNArchipelBOSHResource"]];

    var stropheClient = [TNStropheIMClient IMClientWithService:[[boshService stringValue] lowercaseString] JID:connectionJID password:[password stringValue] rosterClass:TNDatasourceRoster];

    [stropheClient setDelegate:self];
    [stropheClient setDefaultClient];

    [[CPNotificationCenter defaultCenter] postNotificationName:TNConnectionControllerConnectionStarted object:self];
    [stropheClient connect];
}

- (IBAction)rememberCredentials:(id)sender
{
    var defaults = [CPUserDefaults standardUserDefaults];

    if ([credentialRemember isOn])
    {
        [self saveCredentialsInHistory];

        [defaults setObject:[JID stringValue] forKey:@"TNArchipelBOSHJID"];
        [defaults setObject:[password stringValue] forKey:@"TNArchipelBOSHPassword"];
        [defaults setObject:[boshService stringValue] forKey:@"TNArchipelBOSHService"];
        [defaults setBool:YES forKey:@"TNArchipelBOSHRememberCredentials"];
    }
    else
    {
        [self clearCredentialFromHistory];

        [defaults setBool:NO forKey:@"TNArchipelBOSHRememberCredentials"];
        [defaults removeObjectForKey:@"TNArchipelBOSHJID"];
        [defaults removeObjectForKey:@"TNArchipelBOSHPassword"];
    }
}

/*! delegate of TNStropheIMClient
    @param aStropheClient a TNStropheIMClient
    @param anError a string describing the error
*/
- (void)client:(TNStropheIMClient)aStropheClient errorCondition:(CPString)anError
{
    switch (anError)
    {
        case "host-unknown":
            [message setStringValue:CPLocalizedString(@"host-unreachable", @"host-unreachable")];
            break;
        default:
            [message setStringValue:anError || @"Error is unknown because empty"];
    }
    [connectButton setEnabled:YES];
    [connectButton setTitle:CPLocalizedString(@"connect", @"connect")];
    [spinning setHidden:YES];
}

/*! delegate of TNStropheIMClient
    @param aStropheClient TNStropheIMClient
*/
- (void)onStropheConnecting:(TNStropheIMClient)aStropheClient
{
    [message setStringValue:CPLocalizedString(@"connecting", @"connecting")];
    [connectButton setTitle:CPLocalizedString(@"cancel", @"cancel")];
    [connectButton setNeedsLayout];
    [spinning setHidden:NO];
}

/*! delegate of TNStropheIMClient
    @param aStropheClient TNStropheIMClient
*/
- (void)onStropheConnected:(TNStropheIMClient)aStropheClient
{
    [message setStringValue:CPLocalizedString(@"connected", @"connected")];
    [spinning setHidden:YES];

    [[CPNotificationCenter defaultCenter] addObserver:self selector:@selector(_didReceiveUserVCard:) name:TNStropheClientVCardReceivedNotification object:aStropheClient];
    [aStropheClient getVCard];

    CPLog.info(@"Strophe is now connected using JID " + [aStropheClient JID]);
}

/*! delegate of TNStropheIMClient
    @param aStropheClient TNStropheIMClient
*/
- (void)onStropheConnectFail:(TNStropheIMClient)aStropheClient
{
    [spinning setHidden:YES];
    [connectButton setEnabled:YES];
    [connectButton setTitle:CPLocalizedString(@"connect", @"connect")];
    [message setStringValue:CPLocalizedString(@"connection-failed", @"connection-failed")];

    CPLog.info(@"XMPP connection failed");
}

/*! delegate of TNStropheIMClient
    @param aStropheClient TNStropheIMClient
*/
- (void)onStropheAuthenticating:(TNStropheIMClient)aStropheClient
{
    [message setStringValue:CPLocalizedString(@"authenticating", @"authenticating")];
    CPLog.info(@"XMPP authenticating...");
}

/*! delegate of TNStropheIMClient
    @param aStropheClient TNStropheIMClient
*/
- (void)onStropheAuthFail:(TNStropheIMClient)aStropheClient
{
    [spinning setHidden:YES];
    [connectButton setEnabled:YES];
    [connectButton setTitle:CPLocalizedString(@"connect", @"connect")];
    [message setStringValue:CPLocalizedString(@"authentification-failed", @"authentification-failed")];

    [[EKShakeAnimation alloc] initWithView:mainWindow._windowView];
    CPLog.info(@"XMPP auth failed");
}

/*! delegate of TNStropheIMClient
    @param aStropheClient TNStropheIMClient
*/
- (void)onStropheError:(TNStropheIMClient)aStropheClient
{
    [spinning setHidden:YES];
    [connectButton setEnabled:YES];
    [connectButton setTitle:CPLocalizedString(@"connect", @"connect")];
    [message setStringValue:CPLocalizedString(@"unknown-error", @"unknown-error")];

    CPLog.info(@"XMPP unknown error");
}

/*! delegate of TNStropheIMClient
    @param aStropheClient TNStropheIMClient
*/
- (void)onStropheDisconnecting:(TNStropheIMClient)aStropheClient
{
    [spinning setHidden:NO];
    [message setStringValue:CPLocalizedString(@"disconnecting", @"disconnecting")];

    CPLog.info(@"XMPP is disconnecting");
}

/*! delegate of TNStropheIMClient
    @param aStropheClient TNStropheIMClient
*/
- (void)onStropheDisconnected:(TNStropheIMClient)aStropheClient
{
    [spinning setHidden:YES];
    [connectButton setEnabled:YES];
    [connectButton setTitle:CPLocalizedString(@"connect", @"connect")];
    [message setStringValue:CPLocalizedString(@"disconnected", @"disconnected")];

    CPLog.info(@"XMPP connection is now disconnected");
}

@end
