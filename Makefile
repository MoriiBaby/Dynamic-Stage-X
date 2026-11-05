# Dynamic Stage X — source-only build recipe. No CI or remote actions are defined here.
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
PACKAGE_VERSION = 0.1.0~alpha4

# Select a native scheme explicitly. Do not convert an already-built DEB.
#   make package THEOS_PACKAGE_SCHEME=roothide
#   make package THEOS_PACKAGE_SCHEME=rootless
THEOS_PACKAGE_SCHEME ?= roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DynamicStageX
DynamicStageX_FILES = $(sort $(wildcard Sources/*/*.swift) $(wildcard Sources/*/*.m) $(wildcard Sources/*/*.c))
DynamicStageX_CFLAGS = -Wall -Wextra
DynamicStageX_OBJCFLAGS = -fobjc-arc -fobjc-arc-exceptions
DynamicStageX_SWIFTFLAGS = -swift-version 5 -module-name DynamicStageX
DynamicStageX_FRAMEWORKS = UIKit Foundation CoreFoundation CoreGraphics QuartzCore
DynamicStageX_LIBRARIES = substrate

BUNDLE_NAME = DynamicStageXPrefs
DynamicStageXPrefs_FILES = Preferences/DXPreferencesController.swift
DynamicStageXPrefs_SWIFTFLAGS = -swift-version 5 -module-name DynamicStageXPrefs
DynamicStageXPrefs_SWIFT_BRIDGING_HEADER = Preferences/DynamicStageXPrefs-Bridging-Header.h
DynamicStageXPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
DynamicStageXPrefs_PRIVATE_FRAMEWORKS = Preferences
DynamicStageXPrefs_INSTALL_PATH = /Library/PreferenceBundles
DynamicStageXPrefs_RESOURCE_FILES = Preferences/Info.plist

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

# 'stage' may be run by a future authorized build. This target never installs or resprings.
after-stage::
	mkdir -p "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceLoader/Preferences"
	cp layout/Library/PreferenceLoader/Preferences/DynamicStageX.plist "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceLoader/Preferences/DynamicStageX.plist"
