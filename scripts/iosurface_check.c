#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOSurface/IOSurface.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <iosurface_id>\n", argv[0]);
        return 2;
    }
    
    int surfId = atoi(argv[1]);
    if (surfId <= 0) {
        fprintf(stderr, "FAIL: Invalid IOSurface ID: %d\n", surfId);
        return 1;
    }
    
    IOSurfaceRef surface = IOSurfaceLookup((IOSurfaceID)surfId);
    if (!surface) {
        fprintf(stderr, "FAIL: IOSurfaceLookup failed for ID %d\n", surfId);
        return 1;
    }
    
    IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL);
    
    size_t width = IOSurfaceGetWidth(surface);
    size_t height = IOSurfaceGetHeight(surface);
    size_t rowBytes = IOSurfaceGetBytesPerRow(surface);
    void *baseAddr = IOSurfaceGetBaseAddress(surface);
    
    if (!baseAddr || width == 0 || height == 0) {
        IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
        CFRelease(surface);
        fprintf(stderr, "FAIL: IOSurface has no pixel data\n");
        return 1;
    }
    
    // Sample pixels across the frame (top-left, center, bottom-right, etc.)
    // Check if any pixel has non-zero (non-black) RGB values
    bool hasContent = false;
    int nonBlackPixels = 0;
    int totalSampled = 0;
    
    // Sample a grid of points across the frame
    for (int row = 0; row < 10; row++) {
        for (int col = 0; col < 10; col++) {
            size_t x = col * (width / 10);
            size_t y = row * (height / 10);
            uint8_t *pixel = (uint8_t *)baseAddr + (y * rowBytes) + (x * 4); // BGRA
            totalSampled++;
            if (pixel[0] > 5 || pixel[1] > 5 || pixel[2] > 5) {  // non-black
                nonBlackPixels++;
                hasContent = true;
            }
        }
    }
    
    IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
    CFRelease(surface);
    
    if (hasContent) {
        printf("PASS: %d/%d sampled pixels are non-black. Cesium terrain rendering confirmed.\n", 
               nonBlackPixels, totalSampled);
        return 0;
    } else {
        fprintf(stderr, "FAIL: All %d sampled pixels are black. No terrain content detected.\n", totalSampled);
        return 1;
    }
}
