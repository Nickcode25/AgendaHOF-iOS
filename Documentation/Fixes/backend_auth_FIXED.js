// ============================================
// ENDPOINT 4: SOLICITAR REDEFINIÇÃO DE SENHA (VERSÃO CORRIGIDA)
// ============================================

/**
 * POST /api/auth/request-password-reset
 *
 * Gera token OTP e envia email de recuperação de senha
 *
 * Body:
 * {
 *   "email": "usuario@example.com"
 * }
 */
router.post('/request-password-reset', async (req, res) => {
  try {
    const { email } = req.body

    // Validação
    if (!email) {
      return res.status(400).json({ error: 'Email é obrigatório' })
    }

    console.log(`🔐 Gerando link de recuperação para: ${email}`)

    // 1. Gerar link usando admin.generateLink
    const { data: linkData, error: linkError } = await supabase.auth.admin.generateLink({
      type: 'recovery',
      email: email,
      options: {
        redirectTo: process.env.MOBILE_APP_SCHEME || `${process.env.FRONTEND_URL}/reset-password`
      }
    })

    if (linkError) {
      console.error('Erro ao gerar token de recuperação:', linkError)
      // IMPORTANTE: Sempre retorna sucesso para prevenir enumeração de emails
      return res.status(200).json({
        message: 'Email de recuperação enviado (se o email existir)'
      })
    }

    // 2. IMPORTANTE: Extrair o TOKEN OTP, não o access_token
    const actionLink = linkData.properties.action_link
    const url = new URL(actionLink)
    const token = url.searchParams.get('token')  // ← Pegar o 'token', NÃO o 'access_token'

    if (!token) {
      console.error('❌ Token OTP não encontrado no link gerado')
      return res.status(200).json({
        message: 'Email de recuperação enviado (se o email existir)'
      })
    }

    console.log(`✅ Token OTP gerado com sucesso: ${token.substring(0, 20)}...`)

    // 3. Construir o link correto para o app móvel
    const resetLink = `${process.env.SUPABASE_URL}/auth/v1/verify?token=${encodeURIComponent(token)}&type=recovery&redirect_to=${encodeURIComponent(process.env.MOBILE_APP_SCHEME || `${process.env.FRONTEND_URL}/reset-password`)}`

    console.log(`📧 Link de recuperação construído: ${resetLink.substring(0, 100)}...`)

    // 4. Enviar email via Resend
    if (emailTransporter && process.env.RESEND_API_KEY) {
      try {
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
    .button-container {
      text-align: center;
      margin: 30px 0;
    }
    .button {
      display: inline-block;
      padding: 16px 48px;
      background: #ff6b2c;
      color: #ffffff !important;
      text-decoration: none;
      border-radius: 8px;
      font-weight: 600;
      font-size: 16px;
      transition: background 0.3s;
    }
    .button:hover {
      background: #ff8c42;
    }
    .warning-box {
      background: #fff3cd;
      border-left: 4px solid #ffc107;
      padding: 15px;
      margin: 20px 0;
      border-radius: 6px;
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
      <h1>🔑 Redefinir Senha</h1>
    </div>

    <div class="content">
      <p>Olá,</p>

      <p>Recebemos uma solicitação para redefinir a senha da sua conta no <strong>Agenda HOF</strong>.</p>

      <div class="button-container">
        <a href="${resetLink}" class="button">
          Redefinir minha senha
        </a>
      </div>

      <div class="warning-box">
        <p style="margin: 0;"><strong>⚠️ Importante:</strong></p>
        <ul style="margin: 10px 0 0 0; padding-left: 20px;">
          <li>Este link expira em <strong>1 hora</strong></li>
          <li>Só pode ser usado <strong>uma vez</strong></li>
          <li>Se você não solicitou esta redefinição, ignore este email</li>
        </ul>
      </div>

      <p style="font-size: 12px; color: #6c757d; margin-top: 30px;">
        Se o botão não funcionar, copie e cole este link no seu navegador:<br>
        <a href="${resetLink}" style="color: #ff6b2c; word-break: break-all;">${resetLink}</a>
      </p>
    </div>

    <div class="footer">
      <p>
        Este é um email automático do
        <a href="${process.env.FRONTEND_URL}" style="color: #ff6b2c; text-decoration: none;">Agenda HOF</a>
      </p>
      <p>© 2025 Agenda HOF. Todos os direitos reservados.</p>
    </div>
  </div>
</body>
</html>
        `

        const textTemplate = `
Redefinir Senha - Agenda HOF

Olá,

Recebemos uma solicitação para redefinir a senha da sua conta no Agenda HOF.

Clique no link abaixo para criar uma nova senha:
${resetLink}

⚠️ IMPORTANTE:
- Este link expira em 1 hora
- Só pode ser usado uma vez
- Se você não solicitou esta redefinição, ignore este email

---
Agenda HOF - Sistema de Gestão
${process.env.FRONTEND_URL}
        `

        await emailTransporter.emails.send({
          from: `Agenda HOF <${process.env.SMTP_FROM || 'noreply@agendahof.com'}>`,
          to: email,
          subject: '🔑 Redefinir sua senha - Agenda HOF',
          html: htmlTemplate,
          text: textTemplate
        })

        console.log(`✅ Email de recuperação enviado via Resend para ${email}`)
      } catch (emailError) {
        console.error('❌ Erro ao enviar email via Resend:', emailError)
        // Continua mesmo se falhar o envio de email
      }
    } else {
      console.log(`📧 Email de recuperação (modo desenvolvimento para ${email}):`)
      console.log(`Link: ${resetLink}`)
    }

    // Sempre retorna sucesso (mesmo se email não existir)
    res.status(200).json({
      message: 'Email de recuperação enviado (se o email existir)'
    })

  } catch (error) {
    console.error('❌ Erro ao solicitar redefinição de senha:', error)

    // Sempre retorna sucesso para prevenir enumeração
    res.status(200).json({
      message: 'Email de recuperação enviado (se o email existir)'
    })
  }
})
