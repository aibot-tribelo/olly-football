import type { APIRoute } from 'astro';
import { getEntry } from 'astro:content';

export const prerender = true;

export const GET: APIRoute = async () => {
  const gpsEntry = await getEntry('gps', 'gps');
  const gpsDates = gpsEntry.data.sessions
    .filter((s: any) => s.has_data)
    .map((s: any) => s.date);

  const pages = [
    { loc: '/', changefreq: 'weekly', priority: '1.0' },
    { loc: '/footage/', changefreq: 'monthly', priority: '0.7' },
    { loc: '/gps/', changefreq: 'weekly', priority: '0.8' },
    ...gpsDates.map((date: string) => ({
      loc: `/gps/${date}/`,
      changefreq: 'monthly',
      priority: '0.6',
    })),
  ];

  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${pages.map(p => `  <url>
    <loc>https://or9.uk${p.loc}</loc>
    <changefreq>${p.changefreq}</changefreq>
    <priority>${p.priority}</priority>
  </url>`).join('\n')}
</urlset>`;

  return new Response(xml, {
    headers: { 'Content-Type': 'application/xml' },
  });
};
