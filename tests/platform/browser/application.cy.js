// Platform acceptance checks exercise the unchanged application through its public UI.
describe('Local platform contract', () => {
  beforeEach(() => cy.visit('/'));
  it('serves the frontend', () => {
    cy.get('[data-cy="count"]').click().should('have.text', 'count is 1');
  });
  it('reaches the fixed localhost API address from the browser', () => {
    cy.get('input').type('developer');
    cy.get('[data-cy="greet-api"]').click();
    cy.contains('hello, developer').should('be.visible');
  });
  it('reaches PostgreSQL through the API', () => {
    cy.get('[data-cy="greet-db"]').click();
    cy.contains('hello world from postgres').should('be.visible');
  });
});
