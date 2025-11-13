import { NextRequest, NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest) {
  const appToken = request.headers.get('x-app-token');

  if (appToken !== process.env.APP_TOKEN) {
    console.log('❌ Unauthorized request to /api/vision');
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const body = await request.json();
    const { base64Image, prompt, max_tokens } = body;

    console.log('👁️ Vision request');

    const visionRequest = {
      model: 'gpt-4o',
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: prompt },
            {
              type: 'image_url',
              image_url: { url: `data:image/jpeg;base64,${base64Image}` },
            },
          ],
        },
      ],
      max_tokens: max_tokens || 1000,
    };

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      },
      body: JSON.stringify(visionRequest),
    });

    if (!response.ok) {
      const error = await response.text();
      console.error('❌ Vision API error:', response.status, error);
      return NextResponse.json(
        { error: 'Vision API error', details: error },
        { status: response.status }
      );
    }

    const data = await response.json();
    console.log('✅ Vision success');
    return NextResponse.json(data);
  } catch (error: any) {
    console.error('❌ Vision relay error:', error.message);
    return NextResponse.json(
      { error: 'Internal server error', message: error.message },
      { status: 500 }
    );
  }
}

