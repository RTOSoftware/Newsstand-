//
//  PSPDFViewController+Internal.h
//  PSPDFKit
//
//  Copyright (c) 2011-2012 Peter Steinberger. All rights reserved.
//

#import "PSPDFViewController.h"
#import <Foundation/Foundation.h>

@class PSPDFPageView, PSPDFPageCoordinates, PSPDFAnnotation, PSPDFPageInfo, PSPDFLinkAnnotationView;
@protocol PSPDFAnnotationView;

@interface PSPDFViewController (PSPDFInternal)

- (void)delegateWillDisplayDocument;
- (void)delegateDidDisplayDocument;
- (void)delegateDidShowPageView:(PSPDFPageView *)pageView;
- (void)delegateDidRenderPageView:(PSPDFPageView *)pageView;
- (void)delegateDidChangeViewMode:(PSPDFViewMode)viewMode;
- (BOOL)delegateDidTapOnPageView:(PSPDFPageView *)pageView info:(PSPDFPageInfo *)pageInfo coordinates:(PSPDFPageCoordinates *)pageCoordinates;
- (BOOL)delegateDidTapOnAnnotation:(PSPDFAnnotation *)annotation page:(NSUInteger)page info:(PSPDFPageInfo *)pageInfo coordinates:(PSPDFPageCoordinates *)pageCoordinates;
- (BOOL)delegateShouldDisplayAnnotation:(PSPDFAnnotation *)annotation onPageView:(PSPDFPageView *)pageView;
- (UIView <PSPDFAnnotationView> *)delegateViewForAnnotation:(PSPDFAnnotation *)annotation onPageView:(PSPDFPageView *)pageView; // deprecated
- (UIView <PSPDFAnnotationView> *)delegateAnnotationView:(UIView <PSPDFAnnotationView> *)annotationView forAnnotation:(PSPDFAnnotation *)annotation onPageView:(PSPDFPageView *)pageView;
- (void)delegateWillShowAnnotationView:(UIView <PSPDFAnnotationView> *)annotationView onPageView:(PSPDFPageView *)pageView;
- (void)delegateDidShowAnnotationView:(UIView <PSPDFAnnotationView> *)annotationView onPageView:(PSPDFPageView *)pageView;

- (void)delegateDidLoadPageView:(PSPDFPageView *)pageView;
- (void)delegateWillUnloadPageView:(PSPDFPageView *)pageView;

/// causes the annotations to be handled as the receiver sees fit (for example, link annotations are followed).
- (void)handleTouchUpForAnnotationIgnoredByDelegate:(PSPDFLinkAnnotationView *)annotation;

// for PSPDFPageViewController
- (void)setPage:(NSUInteger)page;
- (void)setRealPage:(NSUInteger)page;

// allow checking rotation, for PSPDFSinglePageViewController
@property(nonatomic, assign, getter=isRotationActive, readonly) BOOL rotationActive;

@end
