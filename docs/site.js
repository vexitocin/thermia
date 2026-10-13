const navToggle = document.querySelector('.nav-toggle');
const siteNav = document.querySelector('#site-nav');

navToggle?.addEventListener('click', () => {
    const open = navToggle.getAttribute('aria-expanded') !== 'true';
    navToggle.setAttribute('aria-expanded', String(open));
    navToggle.setAttribute('aria-label', open ? 'Close navigation' : 'Open navigation');
    siteNav?.classList.toggle('is-open', open);
});

siteNav?.addEventListener('click', (event) => {
    if (event.target.closest('a')) {
        navToggle?.setAttribute('aria-expanded', 'false');
        navToggle?.setAttribute('aria-label', 'Open navigation');
        siteNav.classList.remove('is-open');
    }
});

document.querySelectorAll('[data-gallery-scroll]').forEach((button) => {
    button.addEventListener('click', () => {
        const rail = document.querySelector('#screenshot-rail');
        const direction = Number(button.dataset.galleryScroll);
        rail?.scrollBy({ left: direction * 290, behavior: 'smooth' });
    });
});

const year = document.querySelector('#current-year');
if (year) year.textContent = String(new Date().getFullYear());

const releaseLabel = document.querySelector('#release-label');
const releaseVersion = document.querySelector('#release-version');
const releaseLink = document.querySelector('#release-link');

fetch('https://api.github.com/repos/vexitocin/thermia/releases/latest', {
    headers: { Accept: 'application/vnd.github+json' },
})
    .then((response) => {
        if (!response.ok) throw new Error('Latest release unavailable');
        return response.json();
    })
    .then((release) => {
        const version = release.tag_name || 'latest';
        const ipa = release.assets?.find((asset) => asset.name.toLowerCase().endsWith('.ipa'));
        if (releaseLabel) releaseLabel.textContent = `Download ${version}`;
        if (releaseVersion) releaseVersion.textContent = `LATEST RELEASE / ${version}`;
        if (releaseLink) releaseLink.href = ipa?.browser_download_url || release.html_url;
    })
    .catch(() => {
        if (releaseVersion) releaseVersion.textContent = 'CURRENT BUILD / 0.52.1';
    });
