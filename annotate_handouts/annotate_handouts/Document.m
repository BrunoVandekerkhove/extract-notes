//
//  Document.m
//  coursework
//
//  Created by Bruno Vandekerkhove on 13/07/2019.
//  Copyright © 2019 Bruno Vandekerkhove. All rights reserved.
//

#import "Document.h"

#define IDENTIFIER @"Course Work"
#define DEFAULT_FONT [NSFont fontWithName:@"Helvetica-Light" size:14.0]
#define DEFAULT_BOLD_FONT [NSFont fontWithName:@"Helvetica-Bold" size:14.0]

@interface Document ()
@property (weak) IBOutlet PDFView *pdfView;
@property (weak) IBOutlet NSTextView *textView;
@property (weak) IBOutlet NSTextField *statusText;
@end

@implementation Document

#pragma mark Initialization

+ (BOOL)autosavesInPlace {
    return false;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    self.textView.delegate = self;
    self.textView.font = [NSFont fontWithName:@"Helvetica-Light" size:14.0];
    self.pdfView.delegate = self;
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(pageChanged:)
                                               name:PDFViewPageChangedNotification
                                             object:nil];
    self.pdfView.document = document;
    self.pdfView.backgroundColor = [NSColor clearColor];
    self.pdfView.needsDisplay = true;
    self.pdfView.displayMode = kPDFDisplaySinglePage;
    self.pdfView.autoScales = true;
    [self loadPageData];
}

- (void)windowControllerDidLoadNib:(NSWindowController *)windowController {
    [windowController.window zoom:self];
    [windowController.window makeFirstResponder:self.textView];
}

- (NSString *)windowNibName {
    return @"Document";
}

- (void)close {
    [super close];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark Annotations

- (void)pageChanged:(id)sender {
    [self loadPageData];
}

- (void)loadPageData {
    [self saveCurrentPage];
    PDFPage *page = self.pdfView.currentPage;
    NSUInteger pageNumber = [self.pdfView.document indexForPage:self.pdfView.currentPage];
    NSUInteger pageCount = self.pdfView.document.pageCount;
    annotation = nil;
    for (PDFAnnotation *pageAnnotation in page.annotations) {
        if ([pageAnnotation.type isEqualToString:IDENTIFIER]) {
            annotation = pageAnnotation;
            break;
        }
    }
    if (!annotation) {
        annotation = [PDFAnnotation new];
        // annotation = USERNAME;
        annotation.bounds = NSZeroRect;
        annotation.type = IDENTIFIER;
        annotation.contents = @"";
        [page addAnnotation:annotation];
    }
    NSString *text = annotation.contents;
    if (text && text.length > 0) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:text
                                                           options:NSDataBase64DecodingIgnoreUnknownCharacters];
        [self.textView replaceCharactersInRange:NSMakeRange(0, self.textView.string.length)
                                       withRTFD:data];
    }
    else
        self.textView.string = @"";
    [self.textView moveToEndOfDocument:self];
    self.statusText.stringValue = [NSString stringWithFormat:@"Page %li/%li", (pageNumber+1), pageCount];
}

- (void)textDidChange:(NSNotification *)notification {
    [self updateChangeCount:NSChangeDone];
}

- (void)saveCurrentPage {
    NSData *rtf = [self.textView RTFDFromRange:NSMakeRange(0, self.textView.string.length)];
    NSString *string = [rtf base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
    annotation.contents = string;
}

#pragma mark Data

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
    [self saveCurrentPage]; // Not the right place
    return self.pdfView.document.dataRepresentation;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
    document = [[PDFDocument alloc] initWithData:data];
    return true;
}

# pragma mark Actions

- (IBAction)firstSlide:(id)sender {
    [self.pdfView goToFirstPage:sender];
}

- (IBAction)lastSlide:(id)sender {
    [self.pdfView goToLastPage:sender];
}

- (IBAction)previousSlide:(id)sender {
    [self.pdfView goToPreviousPage:sender];
}

- (IBAction)nextSlide:(id)sender {
    [self.pdfView goToNextPage:sender];
}

- (IBAction)clearNotes:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Are you sure?"];
    [alert setInformativeText:@"Clearing notes cannot be undone."];
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.windowControllers.firstObject.window
                  completionHandler:^(NSModalResponse response) {
                      if (response == NSAlertSecondButtonReturn) {
                          for (int i=0 ; i<self.pdfView.document.pageCount ; i++) {
                              PDFPage *page = [self.pdfView.document pageAtIndex:i];
                              for (PDFAnnotation *pageAnnotation in page.annotations) {
                                  if ([pageAnnotation.type isEqualToString:IDENTIFIER])
                                      [page removeAnnotation:pageAnnotation];
                              }
                          }
                          [self updateChangeCount:NSChangeDone];
                          [self loadPageData];
                      }
                      else
                          NSBeep();
                  }];
}

- (IBAction)exportNotes:(id)sender {
    NSTextView *standinTextview = [NSTextView new];
    [standinTextview replaceCharactersInRange:NSMakeRange(0,0) withRTF:[self rtfTitle]];
    for (int i=0 ; i<self.pdfView.document.pageCount ; i++) {
        PDFPage *page = [self.pdfView.document pageAtIndex:i];
        PDFAnnotation *currentAnnotation = nil;
        for (PDFAnnotation *pageAnnotation in page.annotations)
            if ([pageAnnotation.type isEqualToString:IDENTIFIER]) {
                currentAnnotation = pageAnnotation;
                break;
            }
        if (currentAnnotation && currentAnnotation.contents.length > 0) {
            NSData *data = [[NSData alloc] initWithBase64EncodedString:currentAnnotation.contents
                                        options:NSDataBase64DecodingIgnoreUnknownCharacters];
            NSAttributedString *contentString = [[NSAttributedString alloc] initWithRTFD:data documentAttributes:NULL];
            if (contentString.length > 0) {
                [standinTextview replaceCharactersInRange:NSMakeRange(standinTextview.string.length, 0)
                                                  withRTF:[self rtfSeparator:i+1]];
                [standinTextview replaceCharactersInRange:NSMakeRange(standinTextview.string.length, 0)
                                                 withRTFD:data];
            }
        }
    }
    [self saveRTFD:standinTextview];
}

- (NSData *)rtfTitle {
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:self.windowControllers.firstObject.window.title];
    [attributedString addAttribute:NSFontAttributeName value:DEFAULT_BOLD_FONT range:NSMakeRange(0, attributedString.length)];
    NSData *data = [attributedString dataFromRange:(NSRange){0, [attributedString length]} documentAttributes:@{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType} error:NULL];
    return data;
}

- (NSData *)rtfSeparator:(NSUInteger)pageNumber {
    NSString *separatorString = [NSString stringWithFormat:@"\n\nSlide %lu\n\n", pageNumber];
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:separatorString];
    [attributedString addAttribute:NSFontAttributeName value:DEFAULT_BOLD_FONT range:NSMakeRange(0, attributedString.length)];
    NSData *data = [attributedString dataFromRange:(NSRange){0, [attributedString length]} documentAttributes:@{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType} error:NULL];
    return data;
}

- (void)saveRTFD:(NSTextView *)textview {
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setNameFieldStringValue:@"Notes.rtfd"];
    [panel beginSheetModalForWindow:self.windowControllers.firstObject.window completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK)
            [textview writeRTFDToFile:panel.URL.path atomically:true];
        else
            NSBeep();
    }];
}

- (IBAction)reformat:(id)sender {
    self.textView.font = DEFAULT_FONT;
}

@end
