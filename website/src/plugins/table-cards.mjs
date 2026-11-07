// Use the existing Markdown processor's wrapper API to preserve native tables.
export const tableCards = {
  name: 'viku-table-cards',
  element: {
    filter: ['table'],
    visit(node, context) {
      for (let parent = context.parent(node); parent; parent = context.parent(parent)) {
        const classes = parent.properties?.className || [];
        if (classes.includes('not-content') || classes.includes('viku-table-card')) return;
      }
      context.wrapNode(node, {
        type: 'element',
        tagName: 'div',
        properties: {
          className: ['viku-table-card'],
          tabIndex: 0,
          role: 'region',
          ariaLabel: 'Scrollable table',
        },
        children: [],
      });
    },
  },
};
