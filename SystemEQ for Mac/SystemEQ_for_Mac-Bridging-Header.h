//
//  SystemEQ_for_Mac-Bridging-Header.h
//  SystemEQ for Mac
//
//  Bridging header for C libraries used in Swift
//

#ifndef SystemEQ_for_Mac_Bridging_Header_h
#define SystemEQ_for_Mac_Bridging_Header_h

// projectM 4.x C API
#include "Audio/Visualizer/ProjectM/ProjectMBridge.h"

// Lock-free atomics for real-time audio path
#include "Audio/Atomics.h"

#endif /* SystemEQ_for_Mac_Bridging_Header_h */
