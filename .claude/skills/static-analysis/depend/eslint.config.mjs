import depend from 'eslint-plugin-depend';
import json from '@eslint/json';

// ponytail: package.json only — catches the dependency itself, not every import site.
export default [
  {
    files: ['**/package.json'],
    language: 'json/json',
    plugins: {depend, json},
    rules: {'depend/ban-dependencies': 'warn'},
  },
];
