# SwiftBar GitHub Issues Analysis & Implementation Plan

## Last Updated: 2025-01-18

## Issue Analysis & Prioritization

### **HIGH PRIORITY - Critical Bugs (Immediate Action Required)**

1. **#445: Environment Variable Parsing Bug** ⭐⭐⭐⭐⭐ ✅ **DONE**
   - **Impact**: Breaks plugins with complex environment variables
   - **Effort**: Low-Medium (parser fix in `PluginManager.swift`)
   - **Value**: High (affects core functionality)
   - **Status**: **COMPLETED** - Fixed environment variable parsing in commit 3dd4ee3

2. **#442: SwiftBar Not Showing in Menu Bar** ⭐⭐⭐⭐⭐
   - **Impact**: Core functionality broken for some users
   - **Effort**: Medium (needs diagnostic investigation)
   - **Value**: Critical (app unusable without menu bar presence)
   - **Status**: Open - Needs investigation

3. **#443: Plugins Don't Refresh After Sleep** ⭐⭐⭐⭐ ✅ **DONE**
   - **Impact**: Affects user experience with stale data
   - **Effort**: Low-Medium (add wake notification handling)
   - **Value**: High (common user workflow)
   - **Status**: **COMPLETED** - Fixed in ExecutablePlugin.swift start() method

4. **#425: Launch at Login Not Working as Expected** ⭐⭐⭐⭐ ✅ **DONE**
   - **Impact**: App launches at login even when disabled
   - **Effort**: Medium (LaunchAtLogin framework investigation)
   - **Value**: High (user control over app behavior)
   - **Environment**: macOS Sequoia 15.0.1, SwiftBar 2.0.0 (520)
   - **Status**: **COMPLETED** - Replaced LaunchAtLogin package with modern ServiceManagement API implementation for macOS 13.0+ compatibility

### **MEDIUM PRIORITY - User Experience Issues**

5. **#444: Multi-line Display Overflow** ⭐⭐⭐ ✅ **DONE**
   - **Impact**: Visual display issue
   - **Effort**: Low (adjust `menuBarOffset` calculation)
   - **Value**: Medium (affects UI polish)
   - **Status**: **COMPLETED** - Added two-line support with adjusted offset calculation
   - **Milestone**: 2.1.0

6. **#437: Multiple Listings for Single Script** ⭐⭐⭐ ✅ **DONE**
   - **Impact**: Confusing user experience
   - **Effort**: Medium (plugin detection logic)
   - **Value**: Medium (UI cleanup)
   - **Status**: **COMPLETED** - Fixed symlink handling and path deduplication
   - **Milestone**: 2.1.0

7. **#436: .swiftbarignore Not Working** ⭐⭐⭐ ✅ **DONE**
   - **Impact**: Plugin filtering broken
   - **Effort**: Low-Medium (fix ignore file parsing)
   - **Value**: Medium (developer experience)
   - **Status**: **COMPLETED** - Fixed pattern matching to support paths and directories

8. **#422: Show Warning When MenuItem Not Updated** ⭐⭐⭐ **NEW**
   - **Impact**: Users unaware of stale data
   - **Effort**: Medium (implement staleness detection)
   - **Value**: Medium (reliability awareness)
   - **Suggestion**: Visual indicator when item hasn't updated in 2x refresh interval
   - **Status**: Open - Feature request

### **LOW PRIORITY - Enhancement/Polish**

9. **#434: tcsh Export Bug** ⭐⭐ ✅ **DONE**
   - **Impact**: Specific shell compatibility
   - **Effort**: Low (shell-specific export handling)
   - **Value**: Low (niche use case)
   - **Status**: **COMPLETED** - Added shell-specific export syntax for tcsh/csh/fish

10. **#433: Remove Build Number from Release** ⭐ 🚧 **IN PROGRESS**
    - **Impact**: Release process improvement
    - **Effort**: Very Low (UI text change)
    - **Value**: Low (housekeeping)
    - **Status**: Fix implemented on branch `fix-433-remove-build-number`

11. **#412: Folding/Accordion Menu Items** ⭐⭐ **NEW**
    - **Impact**: UI consistency with macOS 14+
    - **Effort**: High (new UI component)
    - **Value**: Low-Medium (UI polish)
    - **Type**: Enhancement
    - **Status**: Open - Feature request for macOS 14 style collapsible menus

### **RESOLVED/DONE**

12. **#438: Shortcut Handle Ignores Header Settings** ✅ **DONE**
    - **Type**: Bug
    - **Status**: Marked as done

13. **#435: Webview Zoom Factor** ✅ **DONE**
    - **Type**: Feature
    - **Status**: Marked as done (enhancement implemented)

14. **#415: Crash on macOS 14.4** ✅ **DONE**
    - **Impact**: App crash on launch
    - **Issue**: AppCenter Crashes error
    - **Status**: Fixed with test build, official release completed

### **INVESTIGATE/MONITOR**

15. **#440: SwiftBar Not Responding** ⭐⭐
    - **Impact**: Unknown (insufficient information)
    - **Effort**: Unknown (needs reproduction)
    - **Value**: Potentially high
    - **Status**: Open - Needs more user feedback

16. **#427: Intermittent M2 Crash** ⭐⭐ ✅ **DONE**
    - **Impact**: Platform-specific stability issue
    - **Environment**: M2 Ventura 13.7
    - **Effort**: High (requires crash debugging)
    - **Value**: Medium (specific hardware)
    - **Status**: **COMPLETED** - Fixed race condition in PluginMetadata deallocation by implementing thread-safe access with concurrent queues

17. **#401: Text Vertical Alignment** ⭐⭐ ✅ **DONE**
    - **Impact**: UI/text alignment issue
    - **Effort**: Medium (UI adjustment)
    - **Value**: Low-Medium (visual polish)
    - **Status**: **COMPLETED** - Fixed default offsets and added valign parameter

18. **#405: Add Support to SF Symbols for Variable Colors** ⭐⭐ ✅ **DONE**
    - **Impact**: Enhanced icon customization
    - **Effort**: Medium (SF Symbols API integration)
    - **Value**: Medium (feature enhancement)
    - **Status**: **COMPLETED** - Added variableValue support via sfconfig and sfvalue parameter

19. **#399: Light/Dark Images Parameter in Dropdown Menu** ⭐⭐ ✅ **DONE**
    - **Impact**: Better theme support
    - **Effort**: Medium (image handling logic)
    - **Value**: Medium (UI consistency)
    - **Status**: **COMPLETED** - Added theme-aware image/SF symbol selection for dropdown vs menu bar

20. **#400: Stopped After Installing Weather Plugin** ⭐⭐⭐ ✅ **DONE**
    - **Impact**: App stability issue
    - **Effort**: Medium (plugin investigation)
    - **Value**: High (app crashes)
    - **Status**: **COMPLETED** - Implemented plugin execution timeout mechanism to prevent hanging plugins from freezing SwiftBar

21. **#387: Plugin with Multiple Files** ⭐ **NEW**
    - **Impact**: Plugin organization improvement
    - **Effort**: High (architecture change)
    - **Value**: Low (developer convenience)
    - **Status**: Open - Opened Sep 24, 2023

## **Recommended Implementation Order**

### Immediate (This Week)
1. **Investigate #442** (menu bar disappearance) - Critical functionality issue
2. **Complete #433** (remove build number) - Already in progress, quick win
3. **Investigate #425** (Launch at Login) - High impact on user experience

### Next Sprint
4. **Implement #422** (stale item warning) - Improves reliability awareness
5. **Debug #440** (not responding) - Gather more information from users

### Future Enhancements
6. **Consider #412** (accordion menus) - UI modernization for macOS 14+

## **Summary**
- **21 total issues** tracked (17 open + 4 recently closed)
- **11 issues completed** (marked with ✅)
- **2 high-priority issues** needing immediate attention
- **3 medium-priority issues** for UX improvements
- **8 lower priority or investigation-needed issues**

## **Key Findings**
- Most critical bugs have been addressed
- Remaining high-priority issues focus on core functionality (menu bar presence, launch behavior)
- Several enhancement requests align with modernizing UI for newer macOS versions
- Good progress on bug fixes with 50% completion rate