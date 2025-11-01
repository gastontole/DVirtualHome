# Arquitectura y target
ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.5

include $(THEOS)/makefiles/common.mk

# Nombre del tweak y archivos
TWEAK_NAME = DVirtualHome
DVirtualHome_FILES = Tweak.xm
DVirtualHome_FRAMEWORKS = UIKit AudioToolbox

# Forzar uso de módulos Clang y evitar conflictos de STL
THEOS_CFLAGS += -fmodules
THEOS_CXXFLAGS += -fmodules
# THEOS_DISABLE_CLANG_MODULES = 1  # Comentado para evitar errores de Darwin

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"

# Comentado para evitar compilación doble
# SUBPROJECTS += dvirtualhome
# include $(THEOS_MAKE_PATH)/aggregate.mk
