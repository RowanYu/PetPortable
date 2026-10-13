const RAWFILE_PREFIX: string = 'resource://rawfile/';
const LIVE2D_ROOT: string = 'live2d/';

function stripQueryAndFragment(url: string): string {
  let end: number = url.length;
  const queryIndex: number = url.indexOf('?');
  const fragmentIndex: number = url.indexOf('#');
  if (queryIndex >= 0) {
    end = queryIndex;
  }
  if (fragmentIndex >= 0 && fragmentIndex < end) {
    end = fragmentIndex;
  }
  return url.substring(0, end);
}

export function isLive2DResourceUrl(url: string): boolean {
  const normalized: string = stripQueryAndFragment(url).replace(/\\/g, '/');
  return normalized.indexOf(RAWFILE_PREFIX + LIVE2D_ROOT) >= 0 ||
    normalized.indexOf('/live2d/') >= 0 ||
    normalized.startsWith(LIVE2D_ROOT) ||
    normalized.startsWith('./' + LIVE2D_ROOT) ||
    normalized.startsWith('models/') ||
    normalized.startsWith('./models/') ||
    normalized.startsWith('libs/') ||
    normalized.startsWith('./libs/');
}

export function resolveLive2DRawPath(url: string): string | null {
  let normalized: string;
  try {
    normalized = decodeURIComponent(stripQueryAndFragment(url)).replace(/\\/g, '/');
  } catch (error) {
    return null;
  }

  const rawfileIndex: number = normalized.indexOf(RAWFILE_PREFIX);
  if (rawfileIndex >= 0) {
    normalized = normalized.substring(rawfileIndex + RAWFILE_PREFIX.length);
  } else {
    const live2DIndex: number = normalized.indexOf('/' + LIVE2D_ROOT);
    if (live2DIndex >= 0) {
      normalized = normalized.substring(live2DIndex + 1);
    }
  }

  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  if (normalized.startsWith('models/') || normalized.startsWith('libs/')) {
    normalized = LIVE2D_ROOT + normalized;
  }

  if (!normalized.startsWith(LIVE2D_ROOT)) {
    return null;
  }

  const segments: string[] = normalized.split('/');
  if (segments.some((segment: string) => segment.length === 0 || segment === '.' || segment === '..')) {
    return null;
  }
  return normalized;
}

export function resolveLive2DMimeType(path: string): string {
  const lower: string = path.toLowerCase();
  if (lower.endsWith('.html')) {
    return 'text/html';
  }
  if (lower.endsWith('.js')) {
    return 'application/javascript';
  }
  if (lower.endsWith('.json')) {
    return 'application/json';
  }
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  return 'application/octet-stream';
}
