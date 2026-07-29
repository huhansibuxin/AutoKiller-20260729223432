ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
INSTALL_TARGET_PROCESSES = com.alipay.iphoneclient

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = AutoKiller

AutoKiller_FILES = Tweak.xm
AutoKiller_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/library.mk
