// Simple Vercel serverless function for testing the relay.
// No Next.js imports, no Google API calls yet.

export default async function handler(req: any, res: any) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed', method: req.method });
    return;
  }

  try {
    const body = req.body || {};
    const query = body.query;
    const num = body.num ?? 3;

    if (!query) {
      res.status(400).json({ error: 'Query is required' });
      return;
    }

    // For now, just echo back what we got so we can see the pipeline is alive.
    res.status(200).json({
      ok: true,
      relay: 'google-search placeholder',
      received: {
        query,
        num,
      },
      message: `Relay is alive. You asked: "${query}".`,
    });
  } catch (error: any) {
    res.status(500).json({
      error: 'Internal server error',
      message: error?.message ?? String(error),
    });
  }
}
