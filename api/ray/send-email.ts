import type { VercelRequest, VercelResponse } from '@vercel/node';
import { sendRayEmail } from '../lib/email/sendRayEmail';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // Only accept POST requests
  if (req.method !== 'POST') {
    return res.status(405).json({ 
      error: 'Method not allowed', 
      message: 'Only POST requests are accepted' 
    });
  }

  // Check x-app-token header
  const appToken = req.headers['x-app-token'];
  if (appToken !== process.env.APP_TOKEN) {
    console.log('❌ Unauthorized request to /api/ray/send-email');
    return res.status(401).json({ error: 'unauthorized' });
  }

  try {
    // Parse JSON body
    const body = req.body || {};
    const { to, subject, html } = body;

    // Defaults
    const emailTo = to || "keithabrown2015@gmail.com";
    const emailSubject = subject || "Test email from Ray (DomeAI)";
    const emailHtml = html || "<p>This is a test email sent from Ray through DomeAI.</p>";

    // Send email
    await sendRayEmail({ 
      to: emailTo, 
      subject: emailSubject, 
      html: emailHtml 
    });

    // Success response
    return res.status(200).json({ 
      ok: true, 
      to: emailTo 
    });

  } catch (error: any) {
    console.error('❌ Error in /api/ray/send-email:', error);
    return res.status(500).json({
      ok: false,
      error: error.message || 'Failed to send email'
    });
  }
}

