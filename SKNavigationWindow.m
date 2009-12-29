//
//  SKNavigationWindow.m
//  Skim
//
//  Created by Christiaan Hofman on 12/19/06.
/*
 This software is Copyright (c) 2006-2009
 Christiaan Hofman. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:

 - Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

 - Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

 - Neither the name of Christiaan Hofman nor the names of any
    contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SKNavigationWindow.h"
#import <Quartz/Quartz.h>
#import "NSBezierPath_SKExtensions.h"
#import "SKPDFView.h"
#import "NSParagraphStyle_SKExtensions.h"
#import "NSGeometry_SKExtensions.h"

#define BUTTON_WIDTH 50.0
#define BUTTON_HEIGHT 50.0
#define SLIDER_WIDTH 100.0
#define SEP_WIDTH 21.0
#define BUTTON_MARGIN 7.0
#define WINDOW_OFFSET 20.0
#define LABEL_OFFSET 10.0
#define LABEL_TEXT_MARGIN 2.0


static inline NSBezierPath *nextButtonPath(NSSize size);
static inline NSBezierPath *previousButtonPath(NSSize size);
static inline NSBezierPath *zoomButtonPath(NSSize size);
static inline NSBezierPath *alternateZoomButtonPath(NSSize size);
static inline NSBezierPath *closeButtonPath(NSSize size);


@implementation SKNavigationWindow

- (id)initWithPDFView:(SKPDFView *)pdfView hasSlider:(BOOL)hasSlider {
    NSScreen *screen = [[pdfView window] screen];
    if (screen == nil)
        screen = [NSScreen mainScreen];
    CGFloat width = 4 * BUTTON_WIDTH + 2 * SEP_WIDTH + 2 * BUTTON_MARGIN;
    if (hasSlider)
        width += SLIDER_WIDTH;
    NSRect contentRect = NSMakeRect(NSMidX([screen frame]) - 0.5 * width, NSMinY([screen frame]) + WINDOW_OFFSET, width, BUTTON_HEIGHT + 2 * BUTTON_MARGIN);
    if (self = [super initWithContentRect:contentRect screen:screen]) {
        
        [self setDisplaysWhenScreenProfileChanges:YES];
        [self setLevel:[[pdfView window] level]];
        [self setHidesOnDeactivate:YES];
        [self setMovableByWindowBackground:YES];
        [self setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
        
        [self setContentView:[[[SKNavigationContentView alloc] init] autorelease]];
        
        NSRect rect = NSMakeRect(BUTTON_MARGIN, BUTTON_MARGIN, BUTTON_WIDTH, BUTTON_HEIGHT);
        previousButton = [[SKNavigationButton alloc] initWithFrame:rect];
        [previousButton setTarget:pdfView];
        [previousButton setAction:@selector(goToPreviousPage:)];
        [previousButton setToolTip:NSLocalizedString(@"Previous", @"Tool tip message")];
        [previousButton setPath:previousButtonPath(rect.size)];
        [previousButton setEnabled:[pdfView canGoToPreviousPage]];
        [[self contentView] addSubview:previousButton];
        
        rect.origin.x = NSMaxX(rect);
        nextButton = [[SKNavigationButton alloc] initWithFrame:rect];
        [nextButton setTarget:pdfView];
        [nextButton setAction:@selector(goToNextPage:)];
        [nextButton setToolTip:NSLocalizedString(@"Next", @"Tool tip message")];
        [nextButton setPath:nextButtonPath(rect.size)];
        [nextButton setEnabled:[pdfView canGoToNextPage]];
        [[self contentView] addSubview:nextButton];
        
        rect.origin.x = NSMaxX(rect);
        rect.size.width = SEP_WIDTH;
        [[self contentView] addSubview:[[[SKNavigationSeparator alloc] initWithFrame:rect] autorelease]];
        
        if (hasSlider) {
            rect.origin.x = NSMaxX(rect);
            rect.size.width = SLIDER_WIDTH;
            zoomSlider = [[SKNavigationSlider alloc] initWithFrame:rect];
            [zoomSlider setTarget:pdfView];
            [zoomSlider setAction:@selector(zoomLog:)];
            [zoomSlider setToolTip:NSLocalizedString(@"Zoom", @"Tool tip message")];
            [zoomSlider setMinValue:log(0.1)];
            [zoomSlider setMaxValue:log(20.0)];
            [zoomSlider setDoubleValue:log([pdfView scaleFactor])];
            [[self contentView] addSubview:zoomSlider];
        }
        
        rect.origin.x = NSMaxX(rect);
        rect.size.width = BUTTON_WIDTH;
        zoomButton = [[SKNavigationButton alloc] initWithFrame:rect];
        [zoomButton setTarget:pdfView];
        [zoomButton setAction:@selector(toggleAutoActualSize:)];
        [zoomButton setToolTip:NSLocalizedString(@"Fit to Screen", @"Tool tip message")];
        [zoomButton setAlternateToolTip:NSLocalizedString(@"Actual Size", @"Tool tip message")];
        [zoomButton setPath:zoomButtonPath(rect.size)];
        [zoomButton setAlternatePath:alternateZoomButtonPath(rect.size)];
        [zoomButton setState:[pdfView autoScales]];
        [zoomButton setButtonType:NSPushOnPushOffButton];
        [[self contentView] addSubview:zoomButton];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleScaleChangedNotification:) 
                                                     name:PDFViewScaleChangedNotification object:pdfView];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePageChangedNotification:) 
                                                     name:PDFViewPageChangedNotification object:pdfView];
        
        rect.origin.x = NSMaxX(rect);
        rect.size.width = SEP_WIDTH;
        [[self contentView] addSubview:[[[SKNavigationSeparator alloc] initWithFrame:rect] autorelease]];
        
        rect.origin.x = NSMaxX(rect);
        rect.size.width = BUTTON_WIDTH;
        closeButton = [[SKNavigationButton alloc] initWithFrame:rect];
        [closeButton setTarget:pdfView];
        [closeButton setAction:@selector(exitFullScreen:)];
        [closeButton setToolTip:NSLocalizedString(@"Close", @"Tool tip message")];
        [closeButton setPath:closeButtonPath(rect.size)];
        [[self contentView] addSubview:closeButton];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    SKDESTROY(previousButton);
    SKDESTROY(nextButton);
    SKDESTROY(zoomButton);
    SKDESTROY(zoomSlider);
    SKDESTROY(closeButton);
    [super dealloc];
}

- (void)moveToScreen:(NSScreen *)screen {
    NSRect winFrame = [self frame];
    winFrame.origin.x = NSMidX([screen frame]) - 0.5 * NSWidth(winFrame);
    winFrame.origin.y = NSMinY([screen frame]) + WINDOW_OFFSET;
    [self setFrame:winFrame display:NO];
}

- (void)orderOut:(id)sender {
    [super orderOut:sender];
    [[SKNavigationToolTipWindow sharedToolTipWindow] orderOut:self];
}

- (void)handleScaleChangedNotification:(NSNotification *)notification {
    [zoomButton setState:[[notification object] autoScales] ? NSOnState : NSOffState];
    [zoomSlider setDoubleValue:log([[notification object] scaleFactor])];
}

- (void)handlePageChangedNotification:(NSNotification *)notification {
    [previousButton setEnabled:[[notification object] canGoToPreviousPage]];
    [nextButton setEnabled:[[notification object] canGoToNextPage]];
}

@end

#pragma mark -

@implementation SKNavigationContentView

- (void)drawRect:(NSRect)rect {
    [[NSGraphicsContext currentContext] saveGraphicsState];
    rect = NSInsetRect([self bounds], 1.0, 1.0);
    [[NSColor colorWithDeviceWhite:0.0 alpha:0.5] set];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:10.0 yRadius:10.0] fill];
    rect = NSInsetRect([self bounds], 0.5, 0.5);
    [[NSColor colorWithDeviceWhite:1.0 alpha:0.2] set];
    [NSBezierPath setDefaultLineWidth:1.0];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:10.0 yRadius:10.0] stroke];
    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

@end

#pragma mark -

@implementation SKNavigationToolTipWindow

+ (id)sharedToolTipWindow {
    static SKNavigationToolTipWindow *sharedToolTipWindow = nil;
    if (sharedToolTipWindow == nil)
        sharedToolTipWindow = [[self alloc] init];
    return sharedToolTipWindow;
}

- (id)init {
    if (self = [super initWithContentRect:NSZeroRect styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES screen:[NSScreen mainScreen]]) {
		[self setBackgroundColor:[NSColor clearColor]];
		[self setOpaque:NO];
        [self setDisplaysWhenScreenProfileChanges:YES];
        [self setReleasedWhenClosed:NO];
        
        toolTipView = [[[SKNavigationToolTipView alloc] init] autorelease];
        [[self contentView] addSubview:toolTipView];
    }
    return self;
}

- (BOOL)canBecomeKeyWindow { return NO; }

- (BOOL)canBecomeMainWindow { return NO; }

- (void)showToolTip:(NSString *)toolTip forView:(NSView *)aView {
    [view release];
    view = [aView retain];
    [toolTipView setStringValue:toolTip];
    [toolTipView sizeToFit];
    NSRect newFrame = [self frameRectForContentRect:[toolTipView frame]];
    NSRect viewRect = [view convertRect:[view bounds] toView:nil];
    viewRect.origin = [[view window] convertBaseToScreen:viewRect.origin];
    newFrame.origin = NSMakePoint(ceil(NSMidX(viewRect) - 0.5 * NSWidth(newFrame)), NSMaxY(viewRect) + LABEL_OFFSET);
    [self setFrame:newFrame display:YES];
    [self setLevel:[[view window] level]];
    if ([self parentWindow] != [view window])
        [[self parentWindow] removeChildWindow:self];
    if ([self parentWindow]  == nil)
        [[view window] addChildWindow:self ordered:NSWindowAbove];
    [self orderFront:self];
}

- (void)orderOut:(id)sender {
    [[self parentWindow] removeChildWindow:self];
    [super orderOut:sender];
    SKDESTROY(view);
}

- (NSView *)view {
    return view;
}

- (BOOL)accessibilityIsIgnored {
    return YES;
}

@end

#pragma mark -

@implementation SKNavigationToolTipView

- (id)initWithFrame:(NSRect)frameRect {
    if (self = [super initWithFrame:frameRect]) {
        stringValue = nil;
    }
    return self;
}

- (void)dealloc {
    SKDESTROY(stringValue);
    [super dealloc];
}

- (NSString *)stringValue {
    return stringValue;
}

- (void)setStringValue:(NSString *)newStringValue {
    if (stringValue != newStringValue) {
        [stringValue release];
        stringValue = [newStringValue retain];
    }
}

- (NSAttributedString *)attributedStringValue {
    if (stringValue == nil)
        return nil;
    NSShadow *aShadow = [[NSShadow alloc] init];
    [aShadow setShadowColor:[NSColor blackColor]];
    [aShadow setShadowBlurRadius:3.0];
    [aShadow setShadowOffset:NSMakeSize(0.0, -1.0)];
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSFont boldSystemFontOfSize:15.0], NSFontAttributeName, 
        [NSColor whiteColor], NSForegroundColorAttributeName, 
        [NSParagraphStyle defaultClippingParagraphStyle], NSParagraphStyleAttributeName, 
        aShadow, NSShadowAttributeName, nil];
    [aShadow release];
    return [[[NSAttributedString alloc] initWithString:stringValue attributes:attrs] autorelease];
}

- (void)sizeToFit {
    NSSize size = [[self attributedStringValue] size];
    size.width = ceil(size.width + 2 * LABEL_TEXT_MARGIN);
    size.height += 2 * LABEL_TEXT_MARGIN;
    [self setFrameSize:size];
}

- (void)drawRect:(NSRect)rect {
    NSRect textRect = NSInsetRect(rect, LABEL_TEXT_MARGIN, LABEL_TEXT_MARGIN);
    NSAttributedString *attrString = [self attributedStringValue];
    // draw it 3x to see some shadow
    [attrString drawInRect:textRect];
    [attrString drawInRect:textRect];
    [attrString drawInRect:textRect];
}

@end

#pragma mark -

@implementation SKNavigationButton

+ (Class)cellClass { return [SKNavigationButtonCell class]; }

- (NSBezierPath *)path {
    return [(SKNavigationButtonCell *)[self cell] path];
}

- (void)setPath:(NSBezierPath *)newPath {
    [(SKNavigationButtonCell *)[self cell] setPath:newPath];
}

- (NSBezierPath *)alternatePath {
    return [(SKNavigationButtonCell *)[self cell] alternatePath];
}

- (void)setAlternatePath:(NSBezierPath *)newAlternatePath {
    [(SKNavigationButtonCell *)[self cell] setAlternatePath:newAlternatePath];
}

- (NSString *)toolTip {
    return [(SKNavigationButtonCell *)[self cell] toolTip];
}

// we don't use the superclass's ivar because we don't want the system toolTips
- (void)setToolTip:(NSString *)string {
    [(SKNavigationButtonCell *)[self cell] setToolTip:string];
    [self setShowsBorderOnlyWhileMouseInside:[string length] > 0];
}

- (NSString *)alternateToolTip {
    return [(SKNavigationButtonCell *)[self cell] alternateToolTip];
}

- (void)setAlternateToolTip:(NSString *)string {
    [(SKNavigationButtonCell *)[self cell] setAlternateToolTip:string];
}

@end

#pragma mark -

@implementation SKNavigationButtonCell

- (id)initTextCell:(NSString *)aString {
    if (self = [super initTextCell:@""]) {
		[self setBezelStyle:NSShadowlessSquareBezelStyle]; // this is mainly to make it selectable
        [self setBordered:NO];
        [self setButtonType:NSMomentaryPushInButton];
    }
    return self;
}

- (void)dealloc {
    SKDESTROY(toolTip);
    SKDESTROY(alternateToolTip);
    SKDESTROY(path);
    SKDESTROY(alternatePath);
    [super dealloc];
}

- (NSString *)toolTip {
    return toolTip;
}

- (void)setToolTip:(NSString *)string {
    if (toolTip != string) {
        [toolTip release];
        toolTip = [string retain];
    }
}

- (NSString *)alternateToolTip {
    return alternateToolTip;
}

- (void)setAlternateToolTip:(NSString *)string {
    if (alternateToolTip != string) {
        [alternateToolTip release];
        alternateToolTip = [string retain];
    }
}

- (NSBezierPath *)path {
    return path;
}

- (void)setPath:(NSBezierPath *)newPath {
    if (path != newPath) {
        [path release];
        path = [newPath retain];
    }
}

- (NSBezierPath *)alternatePath {
    return alternatePath;
}

- (void)setAlternatePath:(NSBezierPath *)newAlternatePath {
    if (alternatePath != newAlternatePath) {
        [alternatePath release];
        alternatePath = [newAlternatePath retain];
    }
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    [[NSColor colorWithDeviceWhite:1.0 alpha:[self isEnabled] == NO ? 0.3 : [self isHighlighted] ? 0.9 : 0.6] setFill];
    [([self state] == NSOnState && [self alternatePath] ? [self alternatePath] : [self path]) fill];
}

- (void)mouseEntered:(NSEvent *)theEvent {
    NSString *currentToolTip = [self state] == NSOnState && alternateToolTip ? alternateToolTip : toolTip;
    [[SKNavigationToolTipWindow sharedToolTipWindow] showToolTip:currentToolTip forView:[self controlView]];
    [super mouseEntered:theEvent];
}

- (void)mouseExited:(NSEvent *)theEvent {
    if ([[[SKNavigationToolTipWindow sharedToolTipWindow] view] isEqual:[self controlView]])
        [[SKNavigationToolTipWindow sharedToolTipWindow] orderOut:nil];
    [super mouseExited:theEvent];
}

- (void)setState:(NSInteger)state {
    NSInteger oldState = [self state];
    NSView *button = [self controlView];
    [super setState:state];
    if (oldState != state && [[button window] isVisible]) {
        if (alternatePath)
            [button setNeedsDisplay:YES];
        if (alternateToolTip && [[[SKNavigationToolTipWindow sharedToolTipWindow] view] isEqual:button]) {
            NSString *currentToolTip = [self state] == NSOnState && alternateToolTip ? alternateToolTip : toolTip;
            [[SKNavigationToolTipWindow sharedToolTipWindow] showToolTip:currentToolTip forView:button];
        }
    }
}

@end

#pragma mark -

@implementation SKNavigationSlider

+ (Class)cellClass { return [SKNavigationSliderCell class]; }

- (id)initWithFrame:(NSRect)frameRect {
    if (self = [super initWithFrame:frameRect]) {
        trackingArea = [[NSTrackingArea alloc] initWithRect:[self bounds] options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways owner:self userInfo:nil];
        [self addTrackingArea:trackingArea];
        toolTip = nil;
    }
    return self;
}

- (void)dealloc {
    SKDESTROY(trackingArea);
    SKDESTROY(toolTip);
    [super dealloc];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    SKDESTROY(trackingArea);
    trackingArea = [[NSTrackingArea alloc] initWithRect:[self bounds] options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways owner:self userInfo:nil];
    [self addTrackingArea:trackingArea];
}

- (NSString *)toolTip {
    return toolTip;
}

- (void)setToolTip:(NSString *)string {
    if (toolTip != string) {
        [toolTip release];
        toolTip = [string retain];
    }
}

- (void)mouseEntered:(NSEvent *)theEvent {
    [[SKNavigationToolTipWindow sharedToolTipWindow] showToolTip:toolTip forView:self];
    if ([[SKNavigationSlider superclass] instancesRespondToSelector:_cmd])
        [super mouseEntered:theEvent];
}

- (void)mouseExited:(NSEvent *)theEvent {
    if ([[[SKNavigationToolTipWindow sharedToolTipWindow] view] isEqual:self])
        [[SKNavigationToolTipWindow sharedToolTipWindow] orderOut:nil];
    if ([[SKNavigationSlider superclass] instancesRespondToSelector:_cmd])
        [super mouseExited:theEvent];
}

@end

#pragma mark -

@implementation SKNavigationSliderCell

- (void)drawBarInside:(NSRect)frame flipped:(BOOL)flipped {
    frame = NSInsetRect(frame, 2.5, 0.0);
    frame.origin.y = NSMidY(frame) - (flipped ? 2.0 : 3.0);
    frame.size.height = 5.0;
	
    CGFloat alpha = [self isEnabled] ? 0.6 : 0.3;
    [[NSColor colorWithDeviceWhite:0.3 alpha:alpha] setFill];
    [[NSColor colorWithDeviceWhite:1.0 alpha:alpha] setStroke];
    
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:frame xRadius:2.0 yRadius:2.0];
    [path fill];
    [path stroke];
}

- (void)drawKnob:(NSRect)frame {
	if ([self isEnabled]) {
        [[NSColor colorWithDeviceWhite:1.0 alpha:[self isHighlighted] ? 0.9 : 0.7] setFill];
        NSShadow *shade = [[NSShadow alloc] init];
        [shade setShadowColor:[NSColor blackColor]];
        [shade setShadowBlurRadius:2.0];
        [shade set];
        [shade release];
    } else {
        [[NSColor colorWithDeviceWhite:1.0 alpha:0.3] setFill];
    }
    
    [[NSBezierPath bezierPathWithOvalInRect:SKRectFromCenterAndSize(SKCenterPoint(frame), SKMakeSquareSize(15.0))] fill];
}

- (BOOL)_usesCustomTrackImage { return YES; }

@end

#pragma mark -

@implementation SKNavigationSeparator

- (void)drawRect:(NSRect)rect {
    NSRect bounds = [self bounds];
    [[NSColor colorWithDeviceWhite:1.0 alpha:0.6] setFill];
    [NSBezierPath fillRect:NSMakeRect(NSMidX(bounds) - 0.5, NSMinY(bounds), 1.0, NSHeight(bounds))];
}

@end

#pragma mark Button paths

static inline NSBezierPath *nextButtonPath(NSSize size) {
    NSRect bounds = {NSZeroPoint, size};
    NSRect rect = NSInsetRect(bounds, 10.0, 10.0);
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(NSMaxX(rect), NSMidY(rect))];
    [path lineToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
    [path lineToPoint:NSMakePoint(NSMinX(rect), NSMinY(rect))];
    [path closePath];
    return path;
}

static inline NSBezierPath *previousButtonPath(NSSize size) {
    NSRect bounds = {NSZeroPoint, size};
    NSRect rect = NSInsetRect(bounds, 10.0, 10.0);
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(NSMinX(rect), NSMidY(rect))];
    [path lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
    [path lineToPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect))];
    [path closePath];
    return path;
}

static inline NSBezierPath *zoomButtonPath(NSSize size) {
    NSRect bounds = {NSZeroPoint, size};
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 15.0, 15.0) xRadius:3.0 yRadius:3.0];
    CGFloat centerX = NSMidX(bounds), centerY = NSMidY(bounds);
    
    [path appendBezierPath:[NSBezierPath bezierPathWithRect:NSInsetRect(bounds, 19.0, 19.0)]];
    
    NSBezierPath *arrow = [NSBezierPath bezierPath];
    [arrow moveToPoint:NSMakePoint(centerX, NSMaxY(bounds) + 2.0)];
    [arrow relativeLineToPoint:NSMakePoint(-5.0, -5.0)];
    [arrow relativeLineToPoint:NSMakePoint(3.0, 0.0)];
    [arrow relativeLineToPoint:NSMakePoint(0.0, -5.0)];
    [arrow relativeLineToPoint:NSMakePoint(4.0, 0.0)];
    [arrow relativeLineToPoint:NSMakePoint(0.0, 5.0)];
    [arrow relativeLineToPoint:NSMakePoint(3.0, 0.0)];
    [arrow relativeLineToPoint:NSMakePoint(-5.0, 5.0)];
    
    NSAffineTransform *transform = [[[NSAffineTransform alloc] init] autorelease];
    [transform translateXBy:centerX yBy:centerY];
    [transform rotateByDegrees:45.0];
    [transform translateXBy:-centerX yBy:-centerY];
    [arrow transformUsingAffineTransform:transform];
    [transform translateXBy:centerX yBy:centerY];
    [transform rotateByDegrees:45.0];
    [transform translateXBy:-centerX yBy:-centerY];
    
    NSInteger i;
    for (i = 0; i < 4; i++) {
        [path appendBezierPath:arrow];
        [arrow transformUsingAffineTransform:transform];
    }
    
    [path setWindingRule:NSEvenOddWindingRule];
    
    return path;
}

static inline NSBezierPath *alternateZoomButtonPath(NSSize size) {
    NSRect bounds = {NSZeroPoint, size};
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 15.0, 15.0) xRadius:3.0 yRadius:3.0];
    CGFloat centerX = NSMidX(bounds), centerY = NSMidY(bounds);
    
    [path appendBezierPath:[NSBezierPath bezierPathWithRect:NSInsetRect(bounds, 19.0, 19.0)]];
    
    NSBezierPath *arrow = [NSBezierPath bezierPath];
    [arrow moveToPoint:NSMakePoint(centerX, NSMaxY(bounds) - 8.0)];
    [arrow relativeLineToPoint:NSMakePoint(-5.0, 5.0)];
    [arrow relativeLineToPoint:NSMakePoint(3.0, 0.0)];
    [arrow relativeLineToPoint:NSMakePoint(0.0, 5.0)];
    [arrow relativeLineToPoint:NSMakePoint(4.0, 0.0)];
    [arrow relativeLineToPoint:NSMakePoint(0.0, -5.0)];
    [arrow relativeLineToPoint:NSMakePoint(3.0, 0.0)];
    [arrow relativeLineToPoint:NSMakePoint(-5.0, -5.0)];
    
    NSAffineTransform *transform = [[[NSAffineTransform alloc] init] autorelease];
    [transform translateXBy:centerX yBy:centerY];
    [transform rotateByDegrees:45.0];
    [transform translateXBy:-centerX yBy:-centerY];
    [arrow transformUsingAffineTransform:transform];
    [transform translateXBy:centerX yBy:centerY];
    [transform rotateByDegrees:45.0];
    [transform translateXBy:-centerX yBy:-centerY];
    
    NSInteger i;
    for (i = 0; i < 4; i++) {
        [path appendBezierPath:arrow];
        [arrow transformUsingAffineTransform:transform];
    }
    
    [path setWindingRule:NSEvenOddWindingRule];
    
    return path;
}

static inline NSBezierPath *closeButtonPath(NSSize size) {
    NSRect bounds = {NSZeroPoint, size};
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat radius = 2.0, halfWidth = 0.5 * NSWidth(bounds) - 15.0, halfHeight = 0.5 * NSHeight(bounds) - 15.0;
    
    [path moveToPoint:NSMakePoint(radius, radius)];
    [path appendBezierPathWithArcWithCenter:NSMakePoint(halfWidth, 0.0) radius:radius startAngle:90.0 endAngle:-90.0 clockwise:YES];
    [path lineToPoint:NSMakePoint(radius, -radius)];
    [path appendBezierPathWithArcWithCenter:NSMakePoint(0.0, -halfHeight) radius:radius startAngle:360.0 endAngle:180.0 clockwise:YES];
    [path lineToPoint:NSMakePoint(-radius, -radius)];
    [path appendBezierPathWithArcWithCenter:NSMakePoint(-halfWidth, 0.0) radius:radius startAngle:270.0 endAngle:90.0 clockwise:YES];
    [path lineToPoint:NSMakePoint(-radius, radius)];
    [path appendBezierPathWithArcWithCenter:NSMakePoint(0.0, halfHeight) radius:radius startAngle:180.0 endAngle:0.0 clockwise:YES];
    [path closePath];
    
    NSAffineTransform *transform = [[[NSAffineTransform alloc] init] autorelease];
    [transform translateXBy:NSMidX(bounds) yBy:NSMidY(bounds)];
    [transform rotateByDegrees:45.0];
    [path transformUsingAffineTransform:transform];
    
    [path appendBezierPath:[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(bounds, 8.0, 8.0)]];
    
    return path;
}
