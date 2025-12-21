#!/bin/bash

# Script para criar projeto Xcode do AgendaHOF

echo "🚀 Criando projeto Xcode para AgendaHOF..."

# Nome do projeto
PROJECT_NAME="AgendaHOF"
BUNDLE_ID="com.agendahof.swift"

# Criar diretório do projeto se não existir
mkdir -p "$PROJECT_NAME.xcodeproj"

# Gerar projeto Xcode a partir do Package.swift
echo "📦 Gerando projeto a partir do Package.swift..."
swift package generate-xcodeproj

# Se falhar, tentar com xcodegen
if [ $? -ne 0 ]; then
    echo "⚠️  Método Package.swift falhou, tentando método alternativo..."

    # Verificar se xcodegen está instalado
    if ! command -v xcodegen &> /dev/null; then
        echo "📥 Instalando xcodegen..."
        brew install xcodegen
    fi

    # Criar arquivo project.yml para xcodegen
    cat > project.yml << EOF
name: $PROJECT_NAME
options:
  bundleIdPrefix: com.agendahof
  deploymentTarget:
    iOS: 17.0
  xcodeVersion: "15.0"

settings:
  base:
    MARKETING_VERSION: 1.0
    CURRENT_PROJECT_VERSION: 1
    DEVELOPMENT_TEAM: ""
    PRODUCT_BUNDLE_IDENTIFIER: $BUNDLE_ID
    TARGETED_DEVICE_FAMILY: 1
    SWIFT_VERSION: 5.9
    IPHONEOS_DEPLOYMENT_TARGET: 17.0
    ENABLE_PREVIEWS: YES
    ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor

targets:
  $PROJECT_NAME:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: .
        excludes:
          - "*.xcodeproj"
          - "*.xcworkspace"
          - ".git"
          - ".build"
          - "DerivedData"
          - "*.sh"
          - "project.yml"
          - "Package.swift"
          - "*.md"
    settings:
      base:
        INFOPLIST_FILE: Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: $BUNDLE_ID
        DEVELOPMENT_TEAM: ""
    dependencies:
      - package: supabase-swift

packages:
  supabase-swift:
    url: https://github.com/supabase/supabase-swift.git
    from: 2.0.0
EOF

    echo "🔨 Gerando projeto com xcodegen..."
    xcodegen generate
fi

echo "✅ Projeto Xcode criado com sucesso!"
echo ""
echo "📝 Próximos passos:"
echo "1. Abra o projeto: open $PROJECT_NAME.xcodeproj"
echo "2. Selecione seu Team de desenvolvimento em Signing & Capabilities"
echo "3. Conecte seu iPhone via USB"
echo "4. Selecione seu iPhone como destino"
echo "5. Clique em Run (▶️) para compilar e instalar"
