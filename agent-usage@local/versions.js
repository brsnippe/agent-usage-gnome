// Release versions (`0.6.0`, `v0.6.1`, `0.6.1-dev+3f2a1c`) for the update
// notice. No GNOME imports, so the tests run it under plain `gjs -m`.

export function parseVersion(text) {
    const match = String(text || '').trim().replace(/^v/, '').match(/^(\d+)\.(\d+)\.(\d+)/);
    return match ? match.slice(1, 4).map(Number) : null;
}

export function compareVersions(a, b) {
    const left = parseVersion(a);
    const right = parseVersion(b);
    if (!left || !right)
        return 0;
    for (let i = 0; i < 3; i++) {
        if (left[i] !== right[i])
            return left[i] < right[i] ? -1 : 1;
    }
    return 0;
}

// A development build of 0.6.0 is not behind release 0.6.0. An install with
// no version at all (from before versions existed) is behind any release.
export function isNewer(candidate, installed) {
    if (!parseVersion(candidate))
        return false;
    if (!parseVersion(installed))
        return true;
    return compareVersions(candidate, installed) > 0;
}
