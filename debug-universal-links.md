# Debug Universal Links - AgendaHOF

## ✅ Status Atual

- **AASA File:** ✅ Válido e acessível
- **Apple CDN:** ✅ Cache da Apple com seu AASA
- **Xcode Config:** ✅ Associated Domains configurado
- **Code:** ✅ Implementação completa

## ❌ Problema

Universal Link abre o Safari em vez do app diretamente.

## 🔧 Solução: Reiniciar iPhone

O iOS faz cache do AASA na primeira instalação. Você adicionou o Associated Domain **depois** da primeira instalação, então o iOS tem cache antigo.

### Passos (EXATAMENTE nesta ordem):

1. **Deletar app do iPhone**
   - Segure o ícone
   - Remover App → Apagar App

2. **REINICIAR O IPHONE** (crítico!)
   - Configurações → Desligar
   - Aguardar 10 segundos
   - Ligar novamente
   
   **Por quê?** Isso limpa o cache de AASA do iOS.

3. **Limpar build no Xcode**
   ```
   Product → Clean Build Folder (Cmd + Shift + K)
   ```

4. **Reinstalar o app**
   ```
   Product → Run (Cmd + R)
   ```

5. **Aguardar 1-2 minutos**
   
   iOS precisa:
   - Detectar novo app instalado
   - Consultar AASA em agendahof.com
   - Registrar Universal Links

6. **Testar no Safari**
   
   Digite na barra de endereço:
   ```
   https://agendahof.com/reset-password
   ```
   
   **Esperado:** App abre diretamente ✅
   
   **Se abrir Safari:** Significa que iOS ainda tem cache antigo. Aguarde mais 5-10 minutos ou repita o processo.

## 🧪 Testes Alternativos

### Teste 1: Forçar pelo banner

Se abrir o Safari:
1. Toque no banner no topo "Agenda HOF"
2. Toque "ABRIR"
3. Isso deve abrir o app
4. Safari vai lembrar da escolha

### Teste 2: Notes/WhatsApp

1. Abra o app Notes ou WhatsApp
2. Cole o link: `https://agendahof.com/reset-password`
3. Toque no link
4. Deve abrir o app diretamente

Links colados em apps nativos (Notes, Messages, WhatsApp) geralmente funcionam melhor que Safari na primeira tentativa.

### Teste 3: Verificar Logs do Xcode

Quando testar, mantenha o Xcode conectado ao iPhone e veja o Console.

**Logs esperados:**
```
🌐 [Universal Link] userActivity.activityType: NSUserActivityTypeBrowsingWeb
🌐 [Universal Link] URL recebida: https://agendahof.com/reset-password
🔗 [Deep Link] Received URL: https://agendahof.com/reset-password
✅ [Deep Link] Token extraído com sucesso
```

**Se não aparecer nada:** iOS não está reconhecendo como Universal Link = cache antigo.

## 📱 Validação Externa

Teste seu AASA online:

https://branch.io/resources/aasa-validator/

1. Acesse o site
2. Cole: `agendahof.com`
3. Clique "Validate"
4. Deve mostrar: ✅ Valid AASA com seu app

## 🚨 Se Ainda Não Funcionar

### Opção 1: Aguardar 24h

Apple CDN faz cache por até 24h. Seu AASA foi atualizado há poucas horas.

### Opção 2: Testar com TestFlight

Universal Links funcionam melhor em builds do TestFlight:

1. Archive o app
2. Upload para TestFlight
3. Instale via TestFlight
4. Teste o link

### Opção 3: Usar Custom URL Scheme (temporário)

Enquanto Universal Links não funciona, configure o Supabase para usar:

```
agendahof://reset-password?access_token={token}&type=recovery
```

Isso já funciona (vimos pelo banner).

## 📊 Timeline Esperado

- **Imediatamente após reinstalar:** Pode não funcionar (cache)
- **Após 1-2 minutos:** Deve começar a funcionar
- **Após 10-15 minutos:** Certamente deve funcionar
- **Após 24h:** Definitivamente deve funcionar

## ✅ Confirmação

Quando funcionar, você verá:

1. Digitar link no Safari
2. App abre IMEDIATAMENTE (sem mostrar site)
3. Tela de reset de senha aparece no app
4. Logs aparecem no Xcode Console

## 🎯 Próximo Passo

**AGORA:** Reinicie o iPhone, reinstale o app, aguarde 2 minutos, teste novamente.

Se não funcionar após 10 minutos: teste via WhatsApp/Notes em vez do Safari.
