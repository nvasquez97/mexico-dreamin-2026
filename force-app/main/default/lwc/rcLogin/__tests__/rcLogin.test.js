// Covers AC-005.5: an already logged-in customer who opens the login page is sent to My shipments
// (the login Apex is only available to visitors), and a visitor sees the login form.
let mockIsGuest = true;

jest.mock('@salesforce/community/basePath', () => ({ __esModule: true, default: '/rutacargo' }), { virtual: true });
jest.mock('@salesforce/apex/CustomerAuthController.login', () => ({ __esModule: true, default: jest.fn() }), { virtual: true });
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

function render(isGuestValue) {
    mockIsGuest = isGuestValue;
    let element;
    jest.isolateModules(() => {
        const { createElement } = require('lwc');
        const RcLogin = require('c/rcLogin').default;
        element = createElement(`c-rc-login-${++renderCount}`, { is: RcLogin });
    });
    document.body.appendChild(element);
    return element;
}

describe('c-rc-login', () => {
    const originalLocation = window.location;

    beforeEach(() => {
        delete window.location;
        window.location = { assign: jest.fn() };
    });

    afterEach(() => {
        window.location = originalLocation;
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('sends a logged-in customer to My shipments instead of showing the form', () => {
        const element = render(false);
        expect(window.location.assign).toHaveBeenCalledWith('/rutacargo/my-shipments');
        expect(element.shadowRoot.querySelector('form')).toBeNull();
    });

    it('shows the login form to a visitor and does not redirect', () => {
        const element = render(true);
        expect(window.location.assign).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('form')).not.toBeNull();
    });
});
