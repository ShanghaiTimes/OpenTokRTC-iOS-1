//
//  RoomViewController.m
//  webrtcDemoiOS
//
//  Created by Song Zheng on 8/14/13.
//  Copyright (c) 2013 Song Zheng. All rights reserved.
//

#import "RoomViewController.h"

#define TABBAR_HEIGHT 49.0f
#define TEXTFIELD_HEIGHT 70.0f
#define MESSAGE_WIDTH 200
#define MESSAGE_CURVE 0
#define MESSAGE_FONTSIZE 13

@interface RoomViewController (){
    NSString* userName;
    NSDictionary* roomInfo;
    NSMutableDictionary* roomUsers;
    NSMutableDictionary* allStreams;
    NSMutableArray* connections;
    OTSession* _session;
    OTPublisher* publisher;
    OTSubscriber* _subscriber;
    
    BOOL initialized;
}

@end

#define SYSTEM_VERSION_LESS_THAN(v)                 ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)

@implementation RoomViewController

@synthesize rid, chatInput, chatTable, chatData, myPickerView, userSelectButton, usersPickerView, selectUserButton, videoContainerView;

- (void)viewDidLoad
{
    [super viewDidLoad];
    //set_ot_log_level(5);
    
    // listen to keyboard events
    [self registerForKeyboardNotifications];
    
    // initialize constants
    roomUsers = [[NSMutableDictionary alloc] init];
    allStreams = [[NSMutableDictionary alloc] init];
    connections= [[NSMutableArray alloc] init];
    chatData = [[NSMutableArray alloc] init];
    initialized = NO;
    
    // add subviews to stream picker for user to pick streams to subscribe to
    [usersPickerView addSubview:myPickerView];
    [usersPickerView addSubview:selectUserButton];
    [usersPickerView setAlpha:0.0];
    
    // listen to taps around the screen, and hide keyboard when necessary
    UITapGestureRecognizer *tgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(viewTapped:)];
    tgr.delegate = self;
    [self.view addGestureRecognizer:tgr];
    
    // set up look of the page
    [self.navigationController setNavigationBarHidden:YES];
    self.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"TBBlue.png"]];
    if (!SYSTEM_VERSION_LESS_THAN(@"7.0")) {
        [self setNeedsStatusBarAppearanceUpdate];
    }
}

- (void)viewDidUnload{
    [super viewDidUnload];
    [self freeKeyboardNotifications];
}

-(UIStatusBarStyle)preferredStatusBarStyle{
    return UIStatusBarStyleLightContent;
}

- (void)viewDidAppear:(BOOL)animated {
    // Send request to get room info (session id and token)
    NSString* roomInfoUrl = [[NSString alloc] initWithFormat:@"https://opentokrtc.com/%@.json", rid];
    NSURL *url = [NSURL URLWithString: roomInfoUrl];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:10];
    [request setHTTPMethod: @"GET"];
    
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error){
        if (error){
            //NSLog(@"Error,%@", [error localizedDescription]);
        }
        else{
            roomInfo = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
            [self setupRoom];
        }
    }];
    
    // Set background appearance
    UIGraphicsBeginImageContext(videoContainerView.frame.size);
    [[UIImage imageNamed:@"silhouetteman.png"] drawInRect:videoContainerView.bounds];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    videoContainerView.backgroundColor = [UIColor colorWithPatternImage:image];
}

- (void) setupRoom {
    // get screen bounds
    CGFloat containerWidth = CGRectGetWidth( videoContainerView.bounds );
    CGFloat containerHeight = CGRectGetHeight( videoContainerView.bounds );
    
    // create publisher and style publisher
    publisher = [[OTPublisher alloc] initWithDelegate:self];
    float diameter = 100.0;
    [publisher.view setFrame:CGRectMake( containerWidth-90, containerHeight-60, diameter, diameter)];
    publisher.view.layer.cornerRadius = diameter/2.0;
    [self.view addSubview:publisher.view];
    
    // add pan gesture to publisher
    UIPanGestureRecognizer *pgr = [[UIPanGestureRecognizer alloc]
                                   initWithTarget:self action:@selector(handlePan:)];
    [publisher.view addGestureRecognizer:pgr];
    pgr.delegate = self;
    publisher.view.userInteractionEnabled = YES;
    
    // Connect to OpenTok session
    NSLog(@"room info: %@", roomInfo);
    
    // Add session event listeners
    OTError *connectError = nil;
    _session = [[OTSession alloc] initWithApiKey:[roomInfo objectForKey:@"apiKey"] sessionId:[roomInfo objectForKey:@"sid"] delegate:self];
    [_session connectWithToken:[roomInfo objectForKey:@"token"] error:&connectError];
    // TODO: handle error
}

- (void) session:(OTSession*)session receivedSignalType:(NSString*)type fromConnection:(OTConnection*)connection
      withString:(NSString*)data
{
    id signalData = [NSJSONSerialization JSONObjectWithData:[data dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:nil];
    
    if ([type isEqualToString:@"initialize"]) {
        if (initialized) {
            return;
        }
        NSDictionary* roomData = (NSDictionary *)signalData; // filters ignored
        // set room users
        NSDictionary* roomDataUsers = (NSDictionary *)[roomData valueForKey:@"users"];
        for (id key in roomDataUsers) {
            [roomUsers setValue:[roomDataUsers objectForKey:key] forKey:key];
        }
        [roomUsers setObject:userName forKey:_session.connection.connectionId];
        [self setSelectStreamButton];
        // set room chat info
        for (id key in (NSArray* )[roomData valueForKey:@"chat"]) {
            [self updateChatTable: (NSDictionary*) key];
        }
        initialized = YES;
    } else if ([type isEqualToString:@"chat"]) {
        [self updateChatTable: (NSDictionary*)signalData];
    } else if ([type isEqualToString:@"name"]) {
        NSArray* nameData = (NSArray* )signalData;
        [roomUsers setObject:[nameData objectAtIndex:1] forKey:[nameData objectAtIndex:0]];
        [self setSelectStreamButton];
    }
}


#pragma mark - Gestures
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if ([touch.view isKindOfClass:[UITextField class]]) {
        NSLog(@"User tapped on UITextField");
    }else{
        [self.chatInput resignFirstResponder];
    }
    return YES;
}
- (void)viewTapped:(UITapGestureRecognizer *)tgr
{
}
- (IBAction)handlePan:(UIPanGestureRecognizer *)recognizer{
    // user is panning publisher object
    CGPoint translation = [recognizer translationInView:publisher.view];
    recognizer.view.center = CGPointMake(recognizer.view.center.x + translation.x,
                                         recognizer.view.center.y + translation.y);
    [recognizer setTranslation:CGPointMake(0, 0) inView:publisher.view];
}



#pragma mark - OpenTok Session
- (void)session:(OTSession*)mySession didCreateConnection:(OTConnection *)connection{
    if (![roomUsers objectForKey:connection.connectionId]) {
        NSString* guestName = [[NSString alloc] initWithFormat:@"Guest-%@", [connection.connectionId substringFromIndex: (connection.connectionId.length - 8)] ];
        [roomUsers setObject: guestName forKey:connection.connectionId];
    }
    [self updateChatTable:@{@"name":userName ,@"text": [[NSString alloc] initWithFormat:@"/serv %@ has joined the room", [roomUsers objectForKey:connection.connectionId] ]}];
    if ([roomUsers count] <= 2) { // me and someone else
        NSDictionary *dataDictionary = @{@"chat":chatData, @"filter": @{}, @"users": roomUsers};
        OTError *signalError = nil;
        NSError *serializationError = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:dataDictionary options:0 error:&serializationError];
        [_session signalWithType:@"initialize" string:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] connection:connection error:&signalError];
        // TODO: handle errors
    }
    NSLog(@"addConnection: %@", roomUsers);
}
- (void)session:(OTSession*)mySession didDropConnection:(OTConnection *)connection{
    [self updateChatTable:@{@"name":userName ,@"text": [[NSString alloc] initWithFormat:@"/serv %@ has left the room", [roomUsers objectForKey:connection.connectionId] ]}];
    [roomUsers removeObjectForKey: connection.connectionId];
    NSLog(@"dropConnection: %@", roomUsers);
}

- (void)sessionDidConnect:(OTSession*)session
{
    userName = [[NSString alloc] initWithFormat:@"Guest-%@", [_session.connection.connectionId substringFromIndex: (_session.connection.connectionId.length - 8)] ];
    if (roomUsers) {
        [roomUsers setObject:userName forKey:_session.connection.connectionId];
    }
    OTError *publishError = nil;
    [_session publish:publisher error:&publishError];
    // TODO: handle error
}

- (void)sessionDidDisconnect:(OTSession*)session
{
    [self leaveRoom];
    _session = nil;
}

- (void) session:(OTSession *)session streamCreated:(OTStream *)stream
{
    // make sure we don't subscribe to ourselves
    if (![stream.connection.connectionId isEqualToString: _session.connection.connectionId] && !_subscriber){
        _subscriber = [[OTSubscriber alloc] initWithStream:stream delegate:self];
        OTError *subscribeError = nil;
        [_session subscribe:_subscriber error:&subscribeError];
        
        // get name of subscribed stream and set the button text to currently subscribed stream
        NSString* streamName = [roomUsers objectForKey: stream.connection.connectionId];
        if (!streamName) {
            streamName = stream.connection.connectionId;
        }
        [userSelectButton setTitle: streamName forState:UIControlStateNormal];
        
        // set width/height of video container view
        CGFloat containerWidth = CGRectGetWidth( videoContainerView.bounds );
        CGFloat containerHeight = CGRectGetHeight( videoContainerView.bounds );
        [_subscriber.view setFrame:CGRectMake( 0, 0, containerWidth, containerHeight)];
        [videoContainerView insertSubview:_subscriber.view belowSubview:publisher.view];
    }
    [allStreams setObject:stream forKey:stream.connection.connectionId];
    
    [connections addObject:stream.connection.connectionId];
    [myPickerView reloadAllComponents];
}

- (void)session:(OTSession *)session streamDestroyed:(OTStream *)stream
{
    NSLog(@"session didDropStream (%@)", stream.streamId);
    
    [allStreams removeObjectForKey:stream.connection.connectionId];
    [connections removeObject:stream.connection.connectionId];
    [myPickerView reloadAllComponents];
}


- (void)session:(OTSession*)session didFailWithError:(OTError*)error {
    NSLog(@"sessionDidFail");
    [self showAlert:[NSString stringWithFormat:@"There was an error connecting to session %@", session.sessionId]];
    [self leaveRoom];
}

- (void)publisher:(OTPublisher*)publisher didFailWithError:(OTError*) error {
    NSLog(@"publisher didFailWithError %@", error);
    [self showAlert:[NSString stringWithFormat:@"There was an error publishing."]];
    [self leaveRoom];
}
- (void)subscriber:(OTSubscriber *)subscriber didFailWithError:(OTError *)error{
    NSLog(@"subscriber could not connect to stream");
}
- (void)subscriberDidConnectToStream:(OTSubscriber *)subscriber{
    NSLog(@"subscriber has successfully connected to stream");
}

#pragma mark - Helper Methods
- (void)leaveRoom{
    if (_session && _session.sessionConnectionStatus==OTSessionConnectionStatusConnecting) {
        NSLog(@"connot quit, currently connecting");
        return;
    }
    if (_session && _session.sessionConnectionStatus==OTSessionConnectionStatusConnected) {
                NSLog(@"connot quit, disconnecting....");
        OTError *disconnectError = nil;
        [_session disconnect:&disconnectError];
        // TODO: handle error
        return;
    }
    _session = NULL;
    _subscriber = NULL;
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)showAlert:(NSString*)string {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Message from video session"
                                                    message:string
                                                   delegate:self
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
}
- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) updateChatTable: (NSDictionary*) msg{
    [chatData addObject: (NSDictionary* )msg ];
    [chatTable reloadData];
    if (chatTable.contentSize.height > chatTable.frame.size.height){
        CGPoint offset = CGPointMake(0, chatTable.contentSize.height - chatTable.frame.size.height);
        [chatTable setContentOffset:offset animated:YES];
    }
}
- (void) setSelectStreamButton{
    for (id key in roomUsers) {
        if ( _subscriber && [_subscriber.stream.connection.connectionId isEqualToString: key] ){
            [userSelectButton setTitle: [roomUsers objectForKey:key] forState:UIControlStateNormal];
        }
    }
    [usersPickerView reloadInputViews];
}



#pragma mark - Chat textfield

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    // called after the text field resigns its first responder status
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    if (chatInput.text.length>0 && userName) {
        // Generate a reference to a new location with childByAutoId, add chat
        OTError *signalError = nil;
        NSDictionary *dataDictionary = @{@"name":userName, @"text": textField.text};
        NSError *serializationError = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:dataDictionary options:0 error:&serializationError];
        [_session signalWithType:@"chat" string:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] connection:nil error:&signalError];
        // TODO: handle errors
        chatInput.text = @"";
    }
    return NO;
}


#pragma mark - ChatList
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [chatData count];
}
- (UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath *)index
{
    static NSString *CellIdentifier = @"chatCellIdentifier";
    ChatCell *cell = [table dequeueReusableCellWithIdentifier:CellIdentifier];
    
    NSDictionary* chatMessage = [chatData objectAtIndex:index.row];
    
    // set width of label
    CGSize maximumLabelSize = CGSizeMake(MESSAGE_WIDTH, FLT_MAX);
    CGSize textSize = [chatMessage[@"text"] sizeWithFont:cell.textString.font constrainedToSize:maximumLabelSize lineBreakMode:cell.textString.lineBreakMode];
    
    // iOS6 and above : Use NSAttributedStrings
    const CGFloat fontSize = MESSAGE_FONTSIZE;
    UIFont *boldFont = [UIFont boldSystemFontOfSize:fontSize];
    UIFont *regularFont = [UIFont systemFontOfSize:fontSize];
    UIColor *foregroundColor = [UIColor colorWithRed:0xDD/255.0f
                                               green:0xDD/255.0f
                                                blue:0xDD/255.0f alpha:1];
    
    // Create the attributes
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           boldFont, NSFontAttributeName,
                           foregroundColor, NSForegroundColorAttributeName, nil];
    NSDictionary *subAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
                              regularFont, NSFontAttributeName, nil];
    
    
    // check for server and user messages, style appropriately via attributes
    if ( ([chatMessage[@"text"] length] >= 6) && ([[chatMessage[@"text"] substringWithRange:NSMakeRange(0, 6)] isEqualToString:@"/serv "]) ) {
        NSMutableString* cellText = [[NSMutableString alloc] initWithFormat:@"%@", [chatMessage[@"text"] substringWithRange:NSMakeRange(6, [chatMessage[@"text"] length]-6)]];
        cell.textString.attributedText = [[NSMutableAttributedString alloc] initWithString:cellText attributes:subAttrs];
        cell.textString.textAlignment = NSTextAlignmentCenter;
    }else{
        const NSRange range = NSMakeRange(0,[chatMessage[@"name"] length]+1); // range of name
        NSMutableString* cellText = [[NSMutableString alloc] initWithFormat:@"%@: %@", chatMessage[@"name"],chatMessage[@"text"]];
        NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:cellText attributes:subAttrs];
        
        [attributedText setAttributes:attrs range:range];
        cell.textString.attributedText = attributedText;
        cell.textString.textAlignment = NSTextAlignmentLeft;
    }
    
    // Create the attributed string (text + attributes)
    
    // set cell string ond style
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    // adjust the label the the new height.
    CGRect newFrame = cell.textString.frame;
    newFrame.size.height = textSize.height;
    cell.textString.frame = newFrame;
    cell.textString.numberOfLines = 0;
    
    //set cell background color
    cell.backgroundColor = [UIColor clearColor];
    
    CALayer * layer = [cell layer];
    layer.masksToBounds = YES;
    layer.cornerRadius = MESSAGE_CURVE;
    
    return cell;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    NSDictionary* chatMessage = [chatData objectAtIndex:indexPath.row];
    
    NSString* myString = chatMessage[@"text"];
    
    // Without creating a cell, just calculate what its height would be
    static int pointsAboveText = 10;
    static int pointsBelowText = 10;
    
    // TODO: there is some code duplication here. In particular, instead of asking the cell, the cell's settings from
    //       the storyboard are manually duplicated here (font, wrapping).
    CGSize maximumLabelSize = CGSizeMake(MESSAGE_WIDTH, FLT_MAX);
    CGFloat expectedLabelHeight = [myString sizeWithFont:[UIFont systemFontOfSize:MESSAGE_FONTSIZE] constrainedToSize:maximumLabelSize lineBreakMode:NSLineBreakByWordWrapping].height;
    
    return pointsAboveText + expectedLabelHeight + pointsBelowText;
}

- (NSIndexPath *)tableView:(UITableView *)tv willSelectRowAtIndexPath:(NSIndexPath *)path
{
    return nil;
}

#pragma mark - Other Interactions
- (IBAction)ExitButton:(id)sender {
    [self leaveRoom];
}

#pragma mark - UIPickerView DataSource
// returns the number of 'columns' to display.
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView
{
    return 1;
}

// returns the # of rows in each component..
- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component
{
    return [connections count];
}

#pragma mark - UIPickerView Delegate
- (CGFloat)pickerView:(UIPickerView *)pickerView rowHeightForComponent:(NSInteger)component
{
    return 50.0;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    return [roomUsers objectForKey: [connections objectAtIndex:row] ];
}

//If the user chooses from the pickerview, it calls this function;
- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
    //Let's print in the console what the user had chosen;
    NSLog(@"Chosen item: %@", [connections objectAtIndex:row]);
}

#pragma mark - User Buttons
- (IBAction)startSelection:(id)sender {
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.5];
    [usersPickerView setAlpha:1.0];
    [UIView commitAnimations];
}

- (IBAction)userSelected:(id)sender {
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.5];
    [usersPickerView setAlpha:0.0];
    [UIView commitAnimations];
    
    int row = [myPickerView selectedRowInComponent:0];
    NSLog(@"user picked row %d", row);
    
    // retrieve stream from user selection
    NSString* streamName = [roomUsers objectForKey: [connections objectAtIndex:row]];
    [userSelectButton setTitle: streamName forState:UIControlStateNormal];
    OTStream* stream = [allStreams objectForKey: [connections objectAtIndex:row]];
    
    // remove old subscriber and create new one
    OTError *unsubscribeError = nil;
    [_session unsubscribe:_subscriber error:&unsubscribeError];
    _subscriber = [[OTSubscriber alloc] initWithStream:stream delegate:self];
    CGFloat containerWidth = CGRectGetWidth( videoContainerView.bounds );
    CGFloat containerHeight = CGRectGetHeight( videoContainerView.bounds );
    [_subscriber.view setFrame:CGRectMake( 0, 0, containerWidth, containerHeight)];
    [videoContainerView insertSubview:_subscriber.view belowSubview:publisher.view];
    
}
- (IBAction)backgroundTap:(id)sender {
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.5];
    [usersPickerView setAlpha:0.0];
    [UIView commitAnimations];
}




#pragma mark - Keyboard notifications
-(void) registerForKeyboardNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWasShown:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}


-(void) freeKeyboardNotifications
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}


-(void) keyboardWasShown:(NSNotification*)aNotification
{
    NSLog(@"Keyboard was shown");
    NSDictionary* info = [aNotification userInfo];
    
    NSTimeInterval animationDuration;
    UIViewAnimationCurve animationCurve;
    CGRect keyboardFrame;
    [[info objectForKey:UIKeyboardAnimationCurveUserInfoKey] getValue:&animationCurve];
    [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] getValue:&animationDuration];
    [[info objectForKey:UIKeyboardFrameBeginUserInfoKey] getValue:&keyboardFrame];
    
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:animationDuration];
    [UIView setAnimationCurve:animationCurve];
    [self.view setFrame:CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y- keyboardFrame.size.height, self.view.frame.size.width, self.view.frame.size.height)];
    
    [UIView commitAnimations];
    
}

-(void) keyboardWillHide:(NSNotification*)aNotification
{
    NSLog(@"Keyboard will hide");
    NSDictionary* info = [aNotification userInfo];
    
    NSTimeInterval animationDuration;
    UIViewAnimationCurve animationCurve;
    CGRect keyboardFrame;
    [[info objectForKey:UIKeyboardAnimationCurveUserInfoKey] getValue:&animationCurve];
    [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] getValue:&animationDuration];
    [[info objectForKey:UIKeyboardFrameBeginUserInfoKey] getValue:&keyboardFrame];
    
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:animationDuration];
    [UIView setAnimationCurve:animationCurve];
    [self.view setFrame:CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y + keyboardFrame.size.height, self.view.frame.size.width, self.view.frame.size.height)];
    
    [UIView commitAnimations];
}



@end


