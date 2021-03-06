//
// AnimatedBlurLabel.swift
//
// Copyright (c) 2015 Mathias Koehnke (http://www.mathiaskoehnke.com)
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

import UIKit

/// The AnimatedBlurLabel class
public class AnimatedBlurLabel : UILabel {
    
    /// The duration of the blurring/unblurring animation in seconds
    public var animationDuration : NSTimeInterval = 10.0
    
    /// The maximum blur radius that is applied to the text
    public var blurRadius : CGFloat = 30.0
    
    /// Returns true if blur has been applied to the text
    public var isBlurred : Bool {
        return !CFEqual(blurLayer1.contents, renderedTextImage?.CGImage)
    }

    /**
    Starts the blurring/unbluring of the text, either with animation or without.
    
    - parameter blurred:    Pass 'true' for blurring the text, 'false' false for unblurring.
    - parameter animated:   Pass 'true' for an animated blurring.
    - parameter completion: The completion handler that is called when the blurring/unblurring
                            animation has finished.
    */
    public func setBlurred(blurred: Bool, animated: Bool, completion: ((finished : Bool) -> Void)?) {
        if animated {
            if canRun() {
                setBlurred(!blurred)
                if reverse == blurred { blurredImages = blurredImages.reverse() }
                completionParameter = completion
                reverse = !blurred
                startDisplayLink()
            } else {
                deferBlur(blurred, animated: animated, completion: completion)
                prepareImages()
            }
        } else {
            setBlurred(blurred)
            callCompletion(completion, finished: true)
        }
    }
    
    //
    // MARK: Private
    //
    
    private lazy var blurLayer1 : CALayer = self.setupBlurLayer()
    private lazy var blurLayer2 : CALayer = self.setupBlurLayer()
    private var blurredImages = [UIImage]()
    private var blurredImagesReady : Bool = false
    private let numberOfStages = 10
    private var reverse : Bool = false
    
    private var blurredParameter : Bool?
    private var animatedParameter : Bool?
    private var completionParameter : ((finished: Bool) -> Void)?
    
    private var renderedTextImage : UIImage?
    private var blurredTextImage : UIImage?
    private var attributedTextToRender: NSAttributedString?
    private var textToRender: String?
    
    private var context : CIContext = {
        let eaglContext = EAGLContext(API: .OpenGLES2)
        let instance = CIContext(EAGLContext: eaglContext, options: [ kCIContextWorkingColorSpace : NSNull() ])
        return instance
    }()
    
    // MARK: Filters
    
    private lazy var clampFilter : CIFilter = {
        let transform = CGAffineTransformIdentity
        let instance = CIFilter(name: "CIAffineClamp")!
        instance.setValue(NSValue(CGAffineTransform: transform), forKey: "inputTransform")
        return instance
    }()
    private lazy var blurFilter : CIFilter = {
        return CIFilter(name: "CIGaussianBlur")!
    }()
    private lazy var colorFilter : CIFilter = {
        let instance = CIFilter(name: "CIConstantColorGenerator")!
        instance.setValue(self.blendColor, forKey: kCIInputColorKey)
        return instance
    }()
    private lazy var blendFilter : CIFilter = {
        return CIFilter(name: "CISourceAtopCompositing")!
    }()
    private lazy var blendColor : CIColor = {
        return CIColor(color: self.backgroundColor ?? self.superview?.backgroundColor ?? .whiteColor())
    }()
    private lazy var inputBackgroundImage : CIImage = {
        return self.colorFilter.outputImage!
    }()
    
    private var startTime : CFTimeInterval?
    private var progress : NSTimeInterval = 0.0
    
    
    // MARK: Label Attributes
    
    override public var textColor: UIColor! {
        didSet {
            resetAttributes()
        }
    }
    
    override public var attributedText: NSAttributedString? {
        set(newValue) {
            attributedTextToRender = newValue
            textToRender = nil
            resetAttributes()
        }
        get {
            return attributedTextToRender
        }
    }
    
    override public var text: String? {
        set(newValue) {
            textToRender = newValue
            attributedTextToRender = nil
            resetAttributes()
        }
        get {
            return textToRender
        }
    }
    
    override public var textAlignment : NSTextAlignment {
        didSet {
            resetAttributes()
        }
    }
    
    override public var font : UIFont! {
        didSet {
            resetAttributes()
        }
    }
    
    override public var lineBreakMode : NSLineBreakMode {
        didSet {
            resetAttributes()
        }
    }
    

    // MARK: Setup
    
    override public func awakeFromNib() {
        super.awakeFromNib()
        
        layer.addSublayer(blurLayer1)
        layer.addSublayer(blurLayer2)
        
        super.text = nil
        super.textAlignment = .Center
    }

    
    private func setupBlurLayer() -> CALayer {
        let layer = CALayer()
        layer.contentsGravity = kCAGravityCenter
        layer.bounds = bounds
        layer.position = center
        layer.contentsScale = UIScreen.mainScreen().scale
        return layer
    }
    
    // MARK: Animation
    
    private lazy var displayLink : CADisplayLink? = {
        var instance = CADisplayLink(target: self, selector: #selector(AnimatedBlurLabel.animateProgress(_:)))
        instance.paused = true
        instance.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSRunLoopCommonModes)
        return instance
    }()
    
    private func startDisplayLink() {
        if (displayLink?.paused == true) {
            progress = 0.0
            startTime = CACurrentMediaTime();
            displayLink?.paused = false
        }
    }
    
    private func stopDisplayLink() {
        displayLink?.paused = true
    }
    
    @objc private func animateProgress(displayLink : CADisplayLink) {
        if (progress > animationDuration) {
            stopDisplayLink()
            setBlurred(!reverse)
            callCompletion(completionParameter, finished: true)
            return
        }
        
        if let startTime = startTime {
            let elapsedTime = CACurrentMediaTime() - startTime
            updateAppearance(elapsedTime)
            self.startTime = CACurrentMediaTime();
        }
    }
    
    private func updateAppearance(elapsedTime : CFTimeInterval?) {
        progress += elapsedTime!
        
        let r = Double(progress / animationDuration)
        let blur = max(0, min(1, r)) * Double(numberOfStages)
        let blurIndex = Int(blur)
        let blurRemainder = blur - Double(blurIndex)
        
        CATransaction.setDisableActions(true)
        blurLayer1.contents = blurredImages[blurIndex + 1].CGImage
        blurLayer2.contents = blurredImages[blurIndex + 2].CGImage
        blurLayer2.opacity = Float(blurRemainder)
        CATransaction.setDisableActions(false)
    }
    
    deinit {
        displayLink!.removeFromRunLoop(NSRunLoop.mainRunLoop(), forMode: NSRunLoopCommonModes)
        displayLink = nil
    }
    
    
    // MARK: Layout
    
    override public func intrinsicContentSize() -> CGSize {
        if let renderedTextImage = renderedTextImage {
            return renderedTextImage.size
        }
        return CGSizeZero
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        
        if CGRectEqualToRect(bounds, blurLayer1.bounds) == false {
            resetAttributes()
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            blurLayer1.frame = bounds
            blurLayer2.frame = bounds
            
            // Text Alignment
            if let renderedTextImage = renderedTextImage where hasAlignment(.Center) == false {
                var newX = (bounds.size.width - renderedTextImage.size.width) / 2
                newX = hasAlignment(.Right) ? newX : (newX * -1)
                blurLayer1.frame = CGRectOffset(blurLayer1.frame, newX, 0)
                blurLayer2.frame = CGRectOffset(blurLayer2.frame, newX, 0)
            }
            
            CATransaction.setDisableActions(false)
            CATransaction.commit()
        }
    }
    
    
    // MARK: Text Rendering
    
    private func resetAttributes() {
        blurredParameter = nil
        animatedParameter = nil
        completionParameter = nil
        
        var text : NSAttributedString?
        if let attributedTextToRender = attributedTextToRender {
            text = attributedTextToRender
        } else if let textToRender = textToRender {
            text = NSAttributedString(string: textToRender, attributes: defaultAttributes())
        }
        
        let maxWidth = preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : bounds.size.width
        let maxHeight = preferredMaxLayoutWidth > 0 ? UIScreen.mainScreen().bounds.size.height : bounds.size.height
        
        renderedTextImage = text?.imageFromText(CGSizeMake(maxWidth, maxHeight))
        if let renderedTextImage = renderedTextImage {
            blurredTextImage = applyBlurEffect(CIImage(image: renderedTextImage)!, blurLevel: Double(blurRadius))
        }
        
        reverse = false
        setBlurred(false)
        
        blurredImagesReady = false
        
        invalidateIntrinsicContentSize()
        layoutIfNeeded()
    }
    
    
    // MARK: Blurring
    
    private func prepareImages() {
        if let renderedTextImage = renderedTextImage {
            if TARGET_IPHONE_SIMULATOR == 1 {
                print("Note: AnimatedBlurLabel is running on the Simulator. " +
                      "Software rendering is used. This might take a few seconds ...")
            }
            
            blurredImagesReady = false
            blurredImages = [UIImage]()
            
            let imageToBlur = CIImage(image: renderedTextImage)!
            let blurredImage = applyBlurEffect(imageToBlur, blurLevel: 0)
            blurredImages.append(blurredImage)
            blurredImages.append(blurredImage)
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { [weak self] in
                if let strongSelf = self {
                    for i in 1...strongSelf.numberOfStages {
                        let radius = Double(i) * Double(strongSelf.blurRadius) / Double(strongSelf.numberOfStages)
                        let blurredImage = strongSelf.applyBlurEffect(imageToBlur, blurLevel: Double(radius))
                        strongSelf.blurredImages.append(blurredImage)
                        
                        if i == strongSelf.numberOfStages {
                            strongSelf.blurredImages.append(blurredImage)
                        }
                    }
                    strongSelf.blurredImagesReady = true
                    
                    if let blurredParameter = strongSelf.blurredParameter,
                        animatedParameter = strongSelf.animatedParameter {
                            dispatch_async(dispatch_get_main_queue(), { [weak self] in
                                self?.setBlurred(blurredParameter, animated: animatedParameter, completion: self?.completionParameter)
                            })
                    }
                }
            }
        }
    }
    
    private func applyBlurEffect(image: CIImage, blurLevel: Double) -> UIImage {
        var resultImage : CIImage = image
        if blurLevel > 0 {
            clampFilter.setValue(image, forKey: kCIInputImageKey)
            let clampResult = clampFilter.outputImage!
            
            blurFilter.setValue(blurLevel, forKey: kCIInputRadiusKey)
            blurFilter.setValue(clampResult, forKey: kCIInputImageKey)
            resultImage = blurFilter.outputImage!
        }
        
        blendFilter.setValue(resultImage, forKey: kCIInputImageKey)
        blendFilter.setValue(inputBackgroundImage, forKey: kCIInputBackgroundImageKey)
        let blendOutput = blendFilter.outputImage!
        
        let offset : CGFloat = CGFloat(blurLevel * 2)
        let cgImage = context.createCGImage(blendOutput, fromRect: CGRectMake(-offset, -offset, image.extent.size.width + (offset*2), image.extent.size.height + (offset*2)))
        let result = UIImage(CGImage: cgImage)
        return result
    }
    
    // MARK: Helper Methods
    
    private func defaultAttributes() -> [String : AnyObject]? {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = lineBreakMode
        paragraph.alignment = textAlignment
        return [NSParagraphStyleAttributeName : paragraph, NSFontAttributeName : font, NSForegroundColorAttributeName : textColor, NSLigatureAttributeName : NSNumber(integer: 0), NSKernAttributeName : NSNumber(float: 0.0)]
    }
    
    private func hasAlignment(alignment: NSTextAlignment) -> Bool {
        var hasAlignment = false
        if let text = attributedTextToRender {
            text.enumerateAttribute(NSParagraphStyleAttributeName, inRange: NSMakeRange(0, text.length), options: [], usingBlock: { value, _ , stop in
                let paragraphStyle = value as? NSParagraphStyle
                hasAlignment = paragraphStyle?.alignment == alignment
                stop.memory = true
            })
        } else if let _ = textToRender {
            hasAlignment = textAlignment == alignment
        }
        return hasAlignment
    }
    
    private func deferBlur(blurred: Bool, animated: Bool, completion: ((finished : Bool) -> Void)?) {
        print("Defer blurring ...")
        blurredParameter = blurred
        animatedParameter = animated
        completionParameter = completion
    }
    
    private func canRun() -> Bool {
        return blurredImagesReady && (completionParameter == nil || (completionParameter != nil && animatedParameter != nil && blurredParameter != nil))
    }
    
    private func setBlurred(blurred: Bool) {
        if blurred {
            blurLayer1.contents = blurredTextImage?.CGImage
            blurLayer2.contents = blurredTextImage?.CGImage
        } else {
            blurLayer1.contents = renderedTextImage?.CGImage
            blurLayer2.contents = renderedTextImage?.CGImage
        }
    }
    
    private func callCompletion(completion: ((finished: Bool) -> Void)?, finished: Bool) {
        self.blurredParameter = nil
        self.animatedParameter = nil
        if let completion = completion {
            self.completionParameter = nil
            completion(finished: finished)
        }
    }
}



private extension NSAttributedString {
    private func sizeToFit(maxSize: CGSize) -> CGSize {
        return boundingRectWithSize(maxSize, options:(NSStringDrawingOptions.UsesLineFragmentOrigin), context:nil).size
    }
    
    private func imageFromText(maxSize: CGSize) -> UIImage {
        let padding : CGFloat = 5
        let size = sizeToFit(maxSize)
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(size.width + padding*2, size.height + padding*2), false , 0.0)
        self.drawInRect(CGRectMake(padding, padding, size.width, size.height))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}