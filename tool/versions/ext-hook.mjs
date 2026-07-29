// boring-avatars 2.0.x ships an ESM build whose relative imports have no file
// extension, which Node's ESM resolver rejects. A bundler would have added it.
// This hook adds it back so the real published package can be loaded as-is —
// no source is modified, so what gets rendered is what npm shipped.
import { existsSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, resolve as resolvePath } from 'node:path';

export async function resolve(specifier, context, next) {
  if (specifier.startsWith('.') && !/\.[cm]?[jt]sx?$/.test(specifier)) {
    const base = dirname(fileURLToPath(context.parentURL));
    for (const candidate of [specifier + '.js', specifier + '/index.js']) {
      const full = resolvePath(base, candidate);
      if (existsSync(full)) {
        return next(pathToFileURL(full).href, context);
      }
    }
  }
  return next(specifier, context);
}
