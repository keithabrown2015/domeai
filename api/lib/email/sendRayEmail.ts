import { Resend } from "resend";

export async function sendRayEmail(options: { to: string; subject: string; html: string }): Promise<void> {
  const resendApiKey = process.env.RESEND_API_KEY;
  const fromEmail = process.env.RAY_FROM_EMAIL;
  const fromName = process.env.RAY_FROM_NAME || "Ray at Dome";

  if (!resendApiKey) {
    throw new Error("RESEND_API_KEY environment variable is not set");
  }

  if (!fromEmail) {
    throw new Error("RAY_FROM_EMAIL environment variable is not set");
  }
  
  // Validate recipient email
  const trimmedTo = (options.to || "").trim();
  if (!trimmedTo) {
    throw new Error("sendRayEmail called without recipient email");
  }
  
  console.log("EMAIL: sending to", trimmedTo, "subject:", options.subject);

  const resend = new Resend(resendApiKey);

  const from = `"${fromName}" <${fromEmail}>`;

  try {
    const result = await resend.emails.send({
      from,
      to: options.to,
      subject: options.subject,
      html: options.html,
    });

    console.log("✅ Email sent successfully:", {
      to: options.to,
      subject: options.subject,
      id: result.data?.id,
    });
  } catch (error: any) {
    console.error("❌ Failed to send email:", {
      to: options.to,
      subject: options.subject,
      error: error.message || "Unknown error",
    });
    throw error;
  }
}

