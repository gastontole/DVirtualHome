# Notas sobre compilación con Theos

## Problema identificado
- Toolchain: Clang 10.0.0 (2020) - muy antiguo
- SDK: iOS 16.5 (2023) - muy nuevo
- Incompatibilidad: Los headers del SDK requieren características que Clang 10 no soporta correctamente

## Soluciones posibles

### 1. Usar un SDK más antiguo (Recomendado)
Descargar un SDK de iOS 14.x o 15.x que sea compatible con Clang 10:
- Colocar en /home/gaston/theos/sdks/
- Actualizar TARGET en Makefile: `TARGET = iphone:clang:15.0:15.0`

### 2. Actualizar toolchain manualmente
- Buscar toolchain más reciente compatible con iOS 16
- Puede requerir compilación desde fuente o descarga manual

### 3. Usar un entorno de desarrollo diferente
- Considerar usar macOS con Xcode para desarrollo
- O usar un toolchain más actualizado si está disponible

## Configuración actual
- Prefix.pch optimizado creado en /home/gaston/theos/Prefix.pch
- Makefile configurado con THEOS_DISABLE_CLANG_MODULES = 1
- DVirtualHome.h incluye stdint.h al inicio
