# --------------------------------------------
# DVirtualHome - Makefile optimizado para iOS 16.5
# Compatible con toolchain ARM64e y Theos Linux
# --------------------------------------------

# Arquitecturas y versión objetivo
ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.5

# Incluir configuración base de Theos
include $(THEOS)/makefiles/common.mk

# Nombre del tweak y sus fuentes
TWEAK_NAME = DVirtualHome
DVirtualHome_FILES = Tweak.xm
DVirtualHome_FRAMEWORKS = UIKit AudioToolbox

# Desactiva los módulos de Clang para evitar conflictos con C++ std
THEOS_DISABLE_CLANG_MODULES = 1

# Compilación con ARC
DVirtualHome_CFLAGS = -fobjc-arc

# Incluir reglas de compilación del tweak
include $(THEOS_MAKE_PATH)/tweak.mk

# Acción después de instalar
after-install::
	install.exec "killall -9 SpringBoard"

# (Desactivado para evitar compilación doble)
# SUBPROJECTS += dvirtualhome
# include $(THEOS_MAKE_PATH)/aggregate.mk