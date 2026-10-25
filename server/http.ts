export const json = (x: unknown, status = 200) => new Response(JSON.stringify(x), { status, headers: { 'content-type': 'application/json' } });
export const leer = (status: number) => new Response(null, { status });

export class TooLarge extends Error {}

// Body in den Speicher, aber nur bis zur Grenze (kleine Bodies: Tresor, JSON).
export async function liesBegrenzt(req: Request, max: number): Promise<Uint8Array> {
  const cl = Number(req.headers.get('content-length'));
  if (cl > max) throw new TooLarge();
  const teile: Uint8Array[] = [];
  let n = 0;
  if (req.body) for await (const t of req.body as any as AsyncIterable<Uint8Array>) {
    n += t.length;
    if (n > max) throw new TooLarge();
    teile.push(t);
  }
  return Buffer.concat(teile);
}
