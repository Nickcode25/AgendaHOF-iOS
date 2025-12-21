#!/bin/bash

# Script para regenerar o projeto Xcode
# Use este script sempre que modificar o project.yml ou adicionar novos arquivos

echo "🔄 Regenerando projeto Xcode..."

# Fechar Xcode se estiver aberto (opcional)
# osascript -e 'quit app "Xcode"'

# Limpar projeto antigo (opcional - descomente se quiser)
# rm -rf AgendaHOF.xcodeproj

# Regenerar projeto
xcodegen generate

if [ $? -eq 0 ]; then
    echo "✅ Projeto regenerado com sucesso!"
    echo ""
    echo "Abrindo projeto..."
    open AgendaHOF.xcodeproj
else
    echo "❌ Erro ao regenerar projeto"
    exit 1
fi
