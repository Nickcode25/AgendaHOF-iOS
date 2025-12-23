// ============================================
// ENDPOINT: NOTIFICAÇÃO DE ALTERAÇÃO DE SENHA (CORRIGIDO COM LOGS)
// ============================================

/**
 * POST /api/auth/password-changed-notification
 *
 * Envia email de notificação ao usuário após alteração de senha
 * VERSÃO CORRIGIDA COM LOGS DETALHADOS
 */
router.post('/password-changed-notification', async (req, res) => {
  try {
    const { email, userId, timestamp } = req.body

    console.log('📧 ========================================')
    console.log('📧 [NOTIFICATION] Request recebido')
    console.log('📧 ========================================')
    console.log('   - Email:', email)
    console.log('   - User ID:', userId)
    console.log('   - Timestamp:', timestamp)

    // Validação
    if (!email || !userId) {
      console.error('❌ [NOTIFICATION] Parâmetros faltando!')
      console.error('   - Email:', email)
      console.error('   - UserId:', userId)
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

    console.log('📅 Data formatada:', formattedDate)

    // Obter informações do request
    const userAgent = req.headers['user-agent'] || 'Desconhecido'
    const ip = req.ip || req.connection.remoteAddress || 'Desconhecido'

    let browser = 'App iOS'
    let os = 'iOS'

    if (userAgent.includes('Chrome')) browser = 'Chrome'
    else if (userAgent.includes('Firefox')) browser = 'Firefox'
    else if (userAgent.includes('Safari') && !userAgent.includes('CriOS')) browser = 'Safari'
    else if (userAgent.includes('Edge')) browser = 'Edge'

    if (userAgent.includes('Windows')) os = 'Windows'
    else if (userAgent.includes('Mac')) os = 'macOS'
    else if (userAgent.includes('Linux')) os = 'Linux'
    else if (userAgent.includes('Android')) os = 'Android'
    else if (userAgent.includes('iPhone') || userAgent.includes('iPad')) os = 'iOS'

    console.log('🖥️  Device info:')
    console.log('   - Browser:', browser)
    console.log('   - OS:', os)
    console.log('   - IP:', ip)
    console.log('   - User-Agent:', userAgent.substring(0, 100))

    // Verificar configuração de email
    console.log('⚙️  Configuração de email:')
    console.log('   - emailTransporter exists:', !!emailTransporter)
    console.log('   - RESEND_API_KEY exists:', !!process.env.RESEND_API_KEY)
    console.log('   - RESEND_API_KEY length:', process.env.RESEND_API_KEY ? process.env.RESEND_API_KEY.length : 0)
    console.log('   - SMTP_FROM:', process.env.SMTP_FROM)

    // Template HTML simplificado para teste
    const htmlTemplate = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
</head>
<body style="font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f4f4f4;">
  <div style="max-width: 600px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px;">
    <h1 style="color: #ff6b2c;">🔒 Sua senha foi alterada</h1>

    <p>Olá,</p>

    <p>Sua senha do <strong>Agenda HOF</strong> foi alterada com sucesso.</p>

    <div style="background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0;">
      <h3 style="margin: 0 0 10px 0; color: #856404;">⚠️ Não foi você?</h3>
      <p style="margin: 0; color: #856404;">Se você não fez essa alteração, sua conta pode estar comprometida.</p>
    </div>

    <div style="background: #f8f9fa; padding: 15px; margin: 20px 0; border-radius: 5px;">
      <p style="margin: 5px 0;"><strong>Data:</strong> ${formattedDate}</p>
      <p style="margin: 5px 0;"><strong>Dispositivo:</strong> ${browser} em ${os}</p>
      <p style="margin: 5px 0;"><strong>IP:</strong> ${ip}</p>
    </div>

    <p style="margin-top: 30px; font-size: 12px; color: #6c757d;">
      Se você reconhece essa alteração, pode ignorar este email com segurança.
    </p>

    <hr style="border: none; border-top: 1px solid #dee2e6; margin: 20px 0;">

    <p style="text-align: center; font-size: 12px; color: #6c757d;">
      Agenda HOF - Sistema de Gestão<br>
      © 2025 Todos os direitos reservados
    </p>
  </div>
</body>
</html>
    `

    const textTemplate = `
Sua senha foi alterada - Agenda HOF

Olá,

Sua senha do Agenda HOF foi alterada com sucesso em ${formattedDate}.

DETALHES:
- Dispositivo: ${browser} em ${os}
- IP: ${ip}

⚠️ NÃO FOI VOCÊ?
Se você não fez essa alteração, sua conta pode estar comprometida.
Redefina sua senha imediatamente.

---
Agenda HOF - Sistema de Gestão
© 2025 Todos os direitos reservados
    `

    console.log('📝 Templates criados')

    // Tentar enviar via Resend
    let emailSent = false

    if (emailTransporter && process.env.RESEND_API_KEY) {
      console.log('📧 Tentando enviar via Resend...')

      try {
        const emailData = {
          from: `Agenda HOF <${process.env.SMTP_FROM || 'noreply@agendahof.com'}>`,
          to: email,
          subject: '🔒 Sua senha foi alterada - Agenda HOF',
          html: htmlTemplate,
          text: textTemplate
        }

        console.log('📧 Dados do email:')
        console.log('   - From:', emailData.from)
        console.log('   - To:', emailData.to)
        console.log('   - Subject:', emailData.subject)
        console.log('   - HTML length:', emailData.html.length)
        console.log('   - Text length:', emailData.text.length)

        console.log('🚀 Chamando Resend API...')
        const startTime = Date.now()

        const result = await emailTransporter.emails.send(emailData)

        const endTime = Date.now()
        emailSent = true

        console.log('✅ ========================================')
        console.log('✅ EMAIL ENVIADO COM SUCESSO!')
        console.log('✅ ========================================')
        console.log('   - Tempo:', (endTime - startTime), 'ms')
        console.log('   - Result:', JSON.stringify(result, null, 2))
        console.log('   - Email ID:', result.id || result.data?.id)

      } catch (resendError) {
        console.error('❌ ========================================')
        console.error('❌ ERRO AO ENVIAR VIA RESEND!')
        console.error('❌ ========================================')
        console.error('📛 Tipo do erro:', typeof resendError)
        console.error('📛 Constructor:', resendError.constructor?.name)
        console.error('📛 Message:', resendError.message)
        console.error('📛 Stack:', resendError.stack)

        // Tentar extrair mais detalhes
        if (resendError.response) {
          console.error('📛 Response:', resendError.response)
        }
        if (resendError.statusCode) {
          console.error('📛 Status Code:', resendError.statusCode)
        }
        if (resendError.body) {
          console.error('📛 Body:', resendError.body)
        }
        if (resendError.error) {
          console.error('📛 Error object:', resendError.error)
        }

        // Logar todas as propriedades do erro
        console.error('📛 Todas as keys do erro:', Object.keys(resendError))
        console.error('📛 Erro completo:', JSON.stringify(resendError, Object.getOwnPropertyNames(resendError), 2))

        console.error('❌ ========================================')
      }
    } else {
      console.warn('⚠️  Email transporter NÃO configurado!')
      console.warn('   - emailTransporter:', !!emailTransporter)
      console.warn('   - RESEND_API_KEY:', !!process.env.RESEND_API_KEY)
    }

    // Se não enviou, logar
    if (!emailSent) {
      console.log('📧 ========================================')
      console.log('📧 EMAIL NÃO FOI ENVIADO (Fallback)')
      console.log('📧 ========================================')
      console.log('Para:', email)
      console.log('Assunto: 🔒 Sua senha foi alterada - Agenda HOF')
      console.log(textTemplate)
      console.log('📧 ========================================')
    }

    console.log('📧 Respondendo ao cliente com 200...')

    // Sempre retorna sucesso para não bloquear o fluxo
    res.status(200).json({
      message: 'Email de notificação enviado com sucesso',
      sent: emailSent,
      debug: {
        hasTransporter: !!emailTransporter,
        hasApiKey: !!process.env.RESEND_API_KEY,
        smtpFrom: process.env.SMTP_FROM
      }
    })

  } catch (error) {
    console.error('❌ ========================================')
    console.error('❌ ERRO GERAL NO ENDPOINT!')
    console.error('❌ ========================================')
    console.error('Tipo:', typeof error)
    console.error('Message:', error.message)
    console.error('Stack:', error.stack)
    console.error('❌ ========================================')

    // Não retorna erro 500 para não bloquear o fluxo
    res.status(200).json({
      message: 'Processado (erro interno silenciado)',
      error: error.message
    })
  }
})
