#!/bin/bash

echo "🧪 Teste de Universal Links - AgendaHOF"
echo "======================================"
echo ""

echo "1️⃣ Validando arquivo AASA..."
curl -s "https://agendahof.com/.well-known/apple-app-site-association" | python3 -m json.tool

echo ""
echo "2️⃣ Verificando cabeçalhos HTTP..."
curl -I "https://agendahof.com/.well-known/apple-app-site-association"

echo ""
echo "3️⃣ Testando CDN da Apple..."
echo "A Apple faz cache do AASA. Verificando se está no cache da Apple CDN..."
curl -I "https://app-site-association.cdn-apple.com/a/v1/agendahof.com"

echo ""
echo "✅ Teste concluído!"
echo ""
echo "📱 Próximos passos:"
echo "1. Deletar o app do iPhone"
echo "2. Reiniciar o iPhone (importante!)"
echo "3. Reinstalar o app"
echo "4. Aguardar 1-2 minutos"
echo "5. Testar novamente"
