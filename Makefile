export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:10.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DVirtualHome
DVirtualHome_FILES = Tweak.xm
DVirtualHome_FRAMEWORKS = UIKit AudioToolbox

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
SUBPROJECTS += dvirtualhome
include $(THEOS_MAKE_PATH)/aggregate.mk
