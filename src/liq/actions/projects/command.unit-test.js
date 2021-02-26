import * as testing from '../../lib/testing'

const shell = require('shelljs')

const execOpts = {
  shell: shell.which('bash'),
  silent: true,
}

describe('liq project', () => {
  // afterAll(() => shell.exit(0))

  test('no action results in error and project help', () => {
    console.error = jest.fn() // supresses err echo from shelljs
    const result = shell.exec(`${testing.LIQ} projects`, execOpts)
    const expectedErr = new RegExp(`No action argument provided.\\s*`)

    expect(result.stderr).toMatch(expectedErr)
    expect(result.stdout.replace(/\033\[\d*m/g, "")).toMatch(testing.expectedCommandGroupUsage(`project`))
    expect(result.code).toBe(10)
  })
})
