// Covers AC-005.5: a logged-in customer sees a Log out link to the site logout page,
// and a visitor sees Log in and Sign up instead. Also checks the official logo files are used.

let mockIsGuest = true;

jest.mock('lightning/platformResourceLoader', () => ({ loadStyle: jest.fn(() => Promise.resolve()) }), { virtual: true });
jest.mock('@salesforce/community/basePath', () => ({ __esModule: true, default: '/rutacargo' }), { virtual: true });
jest.mock('@salesforce/resourceUrl/rcBrand', () => ({ __esModule: true, default: '/resource/rcBrand' }), { virtual: true });
jest.mock(
    '@salesforce/user/isGuest',
    () => ({
        __esModule: true,
        get default() {
            return mockIsGuest;
        }
    }),
    { virtual: true }
);

let renderCount = 0;

// The @salesforce/user/isGuest value is read when the component module loads,
// so each render loads its own copy of the component.
function render(isGuestValue) {
    mockIsGuest = isGuestValue;
    let element;
    jest.isolateModules(() => {
        const { createElement } = require('lwc');
        const RcHeader = require('c/rcHeader').default;
        element = createElement(`c-rc-header-${++renderCount}`, { is: RcHeader });
    });
    document.body.appendChild(element);
    return element;
}

function links(element) {
    return [...element.shadowRoot.querySelectorAll('nav a')].map((a) => ({ text: a.textContent.trim(), href: a.getAttribute('href') }));
}

describe('c-rc-header', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('offers Log out to a logged-in customer (AC-005.5)', () => {
        const element = render(false);
        const logout = links(element).find((l) => l.text === 'Log out');
        expect(logout).toBeDefined();
        expect(logout.href).toBe('/rutacargo/secur/logout.jsp');
        expect(links(element).map((l) => l.text)).toEqual(['Track a shipment', 'Request a shipment', 'My shipments', 'Log out']);
    });

    it('offers Log in and Sign up to a visitor, never Log out', () => {
        const element = render(true);
        expect(links(element).map((l) => l.text)).toEqual(['Track a shipment', 'Log in', 'Sign up']);
    });

    it('uses the official logo files from the brand resource', () => {
        const element = render(true);
        const sources = [...element.shadowRoot.querySelectorAll('img')].map((img) => img.getAttribute('src'));
        expect(sources).toEqual(['/resource/rcBrand/img/logo-color.png', '/resource/rcBrand/img/isotype-tinto.png']);
    });
});
