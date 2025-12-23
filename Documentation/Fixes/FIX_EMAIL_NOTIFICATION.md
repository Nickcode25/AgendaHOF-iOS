# 🔧 Fix: Email de Notificação Não Chega

## 🎯 Problema

O endpoint `/api/auth/password-changed-notification` retorna Status 200, mas o email não chega.

**Causa provável:** Erro silencioso no Resend que não está sendo logado.

---

## 🛠️ Solução: Melhorar Logs do Backend

Substitua o endpoint no arquivo `backend/routes/auth.js` (linhas 66-246):

### Mudança na linha 177-182:

**❌ Antes (erro silenciado):**
```javascript
} catch (resendError) {
  console.warn('Erro ao enviar via Resend:', resendError)
}
```

**✅ Depois (log completo):**
```javascript
} catch (resendError) {
  console.error('❌ ERRO COMPLETO ao enviar via Resend:', {
    error: resendError,
    message: resendError.message,
    stack: resendError.stack,
    email: email,
    from: process.env.SMTP_FROM
  })
}
```

---

## 📋 Código Completo Corrigido

Substitua todo o endpoint `/password-changed-notification` por:

```javascript
router.post('/password-changed-notification', async (req, res) => {
  try {
    const { email, userId, timestamp } = req.body

    console.log(`📧 [Notification] Recebido request para: ${email}`)

    // Validação
    if (!email || !userId) {
      console.error('❌ [Notification] Parâmetros faltando:', { email, userId })
      return res.status(400).json({ error: 'Email e userId são obrigatórios' })
    }

    // Formatar data/hora
    const date = new Date(timestamp || new Date())
    const formattedDate = date.toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    })

    // Obter informações adicionais do request
    const userAgent = req.headers['user-agent'] || 'Desconhecido'
    const ip = req.ip || req.connection.remoteAddress || 'Desconhecido'

    // Detectar navegador e sistema operacional
    let browser = 'Navegador'
    let os = 'Sistema'

    if (userAgent.includes('Chrome')) browser = 'Chrome'
    else if (userAgent.includes('Firefox')) browser = 'Firefox'
    else if (userAgent.includes('Safari')) browser = 'Safari'
    else if (userAgent.includes('Edge')) browser = 'Edge'

    if (userAgent.includes('Windows')) os = 'Windows'
    else if (userAgent.includes('Mac')) os = 'macOS'
    else if (userAgent.includes('Linux')) os = 'Linux'
    else if (userAgent.includes('Android')) os = 'Android'
    else if (userAgent.includes('iOS')) os = 'iOS'

    console.log(`📧 [Notification] Preparando email para ${email}`)
    console.log(`   - Device: ${browser} em ${os}`)
    console.log(`   - IP: ${ip}`)
    console.log(`   - Data: ${formattedDate}`)

    // Template HTML do email
    const htmlTemplate = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      margin: 0;
      padding: 0;
      background-color: #f4f4f4;
    }
    .container {
      max-width: 600px;
      margin: 40px auto;
      background: #ffffff;
      border-radius: 12px;
      overflow: hidden;
      box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
    }
    .header {
      background: linear-gradient(135deg, #ff6b2c 0%, #ff8c42 100%);
      padding: 30px;
      text-align: center;
    }
    .header h1 {
      color: #ffffff;
      margin: 0;
      font-size: 24px;
      font-weight: 600;
    }
    .content {
      padding: 40px 30px;
    }
    .alert-box {
      background: #fff3cd;
      border-left: 4px solid #ffc107;
      padding: 20px;
      margin: 20px 0;
      border-radius: 6px;
    }
    .alert-box h3 {
      margin: 0 0 10px 0;
      color: #856404;
      font-size: 18px;
    }
    .info-box {
      background: #f8f9fa;
      border: 1px solid #dee2e6;
      padding: 20px;
      margin: 20px 0;
      border-radius: 6px;
    }
    .info-row {
      display: flex;
      justify-content: space-between;
      padding: 8px 0;
      border-bottom: 1px solid #e9ecef;
    }
    .info-row:last-child {
      border-bottom: none;
    }
    .button {
      display: inline-block;
      padding: 14px 32px;
      background: #dc3545;
      color: #ffffff !important;
      text-decoration: none;
      border-radius: 8px;
      font-weight: 600;
      margin: 10px;
    }
    .footer {
      background: #f8f9fa;
      padding: 20px;
      text-align: center;
      font-size: 12px;
      color: #6c757d;
      border-top: 1px solid #dee2e6;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🔒 Sua senha foi alterada</h1>
    </div>

    <div class="content">
      <p>Olá,</p>
      <p>Sua senha do <strong>Agenda HOF</strong> foi alterada com sucesso.</p>

      <div class="alert-box">
        <h3>⚠️ Não foi você?</h3>
        <p>Se você não fez essa alteração, sua conta pode estar comprometida.</p>
      </div>

      <div class="info-box">
        <div class="info-row">
          <span><strong>Data:</strong></span>
          <span>${formattedDate}</span>
        </div>
        <div class="info-row">
          <span><strong>Dispositivo:</strong></span>
          <span>${browser} em ${os}</span>
        </div>
        <div class="info-row">
          <span><strong>IP:</strong></span>
          <span>${ip}</span>
        </div>
      </div>

      <div style="text-align: center; margin: 30px 0;">
        <a href="${process.env.FRONTEND_URL || 'https://agendahof.com'}/forgot-password" class="button">
          Redefinir senha novamente
        </a>
      </div>
    </div>

    <div class="footer">
      <p>Agenda HOF - Sistema de Gestão</p>
      <p>© 2025 Agenda HOF. Todos os direitos reservados.</p>
    </div>
  </div>
</body>
</html>
    `

    const textTemplate = `
Sua senha foi alterada - Agenda HOF

Sua senha foi alterada com sucesso em ${formattedDate}.

Dispositivo: ${browser} em ${os}
IP: ${ip}

⚠️ NÃO FOI VOCÊ?
Se você não fez essa alteração, redefina sua senha imediatamente.

---
Agenda HOF - Sistema de Gestão
    `

    // Tentar enviar via Resend
    let emailSent = false

    console.log(`📧 [Notification] Verificando emailTransporter:`, {
      hasTransporter: !!emailTransporter,
      hasResendKey: !!process.env.RESEND_API_KEY,
      smtpFrom: process.env.SMTP_FROM
    })

    if (emailTransporter && process.env.RESEND_API_KEY) {
      try {
        console.log(`📧 [Notification] Tentando enviar via Resend...`)

        const result = await emailTransporter.emails.send({
          from: `Agenda HOF <${process.env.SMTP_FROM || 'noreply@agendahof.com'}>`,
          to: email,
          subject: '🔒 Sua senha foi alterada - Agenda HOF',
          html: htmlTemplate,
          text: textTemplate
        })

        emailSent = true
        console.log(`✅ [Notification] Email enviado via Resend para ${email}`)
        console.log(`   - Result:`, result)

      } catch (resendError) {
        console.error('❌ [Notification] ERRO COMPLETO ao enviar via Resend:')
        console.error('   - Error object:', resendError)
        console.error('   - Error message:', resendError.message)
        console.error('   - Error stack:', resendError.stack)
        console.error('   - Email destino:', email)
        console.error('   - SMTP_FROM:', process.env.SMTP_FROM)
        console.error('   - Tipo do erro:', typeof resendError)
        console.error('   - Keys do erro:', Object.keys(resendError))

        // Tentar extrair mais detalhes do erro do Resend
        if (resendError.response) {
          console.error('   - Response:', resendError.response)
        }
        if (resendError.statusCode) {
          console.error('   - Status Code:', resendError.statusCode)
        }
      }
    } else {
      console.warn(`⚠️ [Notification] Email transporter não configurado`)
      console.log(`   - emailTransporter exists: ${!!emailTransporter}`)
      console.log(`   - RESEND_API_KEY exists: ${!!process.env.RESEND_API_KEY}`)
    }

    // Se não enviou, logar no console (desenvolvimento)
    if (!emailSent) {
      console.log('📧 [Notification] Email NÃO foi enviado! (modo fallback)')
      console.log(`Para: ${email}`)
      console.log(textTemplate)
    }

    // Sempre retorna sucesso para não bloquear o fluxo
    res.status(200).json({
      message: 'Email de notificação enviado com sucesso'
    })

  } catch (error) {
    console.error('❌ [Notification] ERRO GERAL no endpoint:', error)
    console.error('   - Stack:', error.stack)

    // Não retorna erro 500 para não bloquear o fluxo
    res.status(200).json({
      message: 'Processado (erro interno silenciado)'
    })
  }
})
```

---

## ✅ Como Aplicar

1. **Copie o código acima**
2. **Cole no arquivo** `backend/routes/auth.js`
3. **Substitua** todo o endpoint `/password-changed-notification` (linhas 66-246)
4. **Faça commit e push**:
   ```bash
   git add backend/routes/auth.js
   git commit -m "fix: Melhorar logs de email de notificação"
   git push
   ```
5. **Aguarde deploy do Railway** (~2 minutos)
6. **Teste novamente** a redefinição de senha
7. **Verifique os logs do Railway** para ver o erro completo

---

## 🔍 Possíveis Causas do Erro

1. **SMTP_FROM não configurado** ou email não verificado no Resend
2. **RESEND_API_KEY inválida** ou expirada
3. **Email destino** na blocklist do Resend
4. **Limite de envios** do Resend atingido
5. **Formato de email** `from` incorreto

Os novos logs vão revelar exatamente qual é o problema!

---

**Última atualização:** 2025-12-23
