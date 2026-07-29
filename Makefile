export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = com.alipay.iphoneclient
export THEOS_PACKAGE_SCHEME = rootless
export _THEOS_PLATFORM_DPKG_DEB_COMPRESSION = gzip

TWEAK_NAME = AutoKiller

AutoKiller_FILES = Tweak.xm
AutoKiller_CFLAGS = -fobjc-arc
AutoKiller_LIBRARIES += substrate
AutoKiller_LOGOSFLAGS += -c generator=MobileSubstrate
AutoKiller_FRAMEWORKS = Foundation UIKit

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk