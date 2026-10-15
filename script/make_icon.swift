import AppKit
let image = NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus()
let shape = NSBezierPath(roundedRect:NSRect(x:42,y:42,width:940,height:940),xRadius:218,yRadius:218)
NSGradient(colors:[NSColor(calibratedRed:0.95,green:0.98,blue:1,alpha:1),NSColor(calibratedRed:0.67,green:0.81,blue:1,alpha:1)])!.draw(in:shape,angle:-70)
NSColor.white.withAlphaComponent(0.8).setStroke(); shape.lineWidth = 6; shape.stroke()
let symbol = "✌︎" as NSString
let style = NSMutableParagraphStyle(); style.alignment = .center
symbol.draw(in:NSRect(x:65,y:110,width:900,height:770),withAttributes:[.font:NSFont.systemFont(ofSize:690,weight:.ultraLight),.foregroundColor:NSColor.systemBlue,.paragraphStyle:style])
image.unlockFocus()
let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
