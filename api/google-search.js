export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const appToken = req.headers['x-app-token'];
  if (appToken !== process.env.APP_TOKEN) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    const { query } = req.body;

    if (!query) {
      return res.status(400).json({ error: 'Query is required' });
    }

    const searchURL = `https://www.googleapis.com/customsearch/v1?key=${process.env.GOOGLE_API_KEY}&cx=${process.env.GOOGLE_SEARCH_ENGINE_ID}&q=${encodeURIComponent(query)}`;

    const response = await fetch(searchURL);

    if (!response.ok) {
      const error = await response.text();
      console.error('Google Search API Error:', error);
      return res.status(response.status).json({ error: 'Google Search API error' });
    }

    const data = await response.json();
    return res.status(200).json(data);
  } catch (error) {
    console.error('Search relay error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

