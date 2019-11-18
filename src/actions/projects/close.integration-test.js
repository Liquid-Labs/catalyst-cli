import * as testing from '../../lib/testing'

const shell = require('shelljs')

const execOpts = {
  shell: shell.which('bash'),
  silent: true,
}

describe(`Command 'liq projects close'`, () => {
  let setupConfig
  let playground
  beforeEach(() => {
    setupConfig = testing.setup()
    setupConfig.metaInit()
    setupConfig.localCheckout()
  })
  afterEach(() => setupConfig.cleanup())

  const closeFailureTests = [
    { desc: `should do nothing and emit warning if there are untracked files.`,
      setup: (setupConfig) => shell.exec(`cd ${setupConfig.localRepoCheckout} && touch foobar`, execOpts),
      // TODO: having trouble matching end to end because of the non-printing coloration characters.
      errMatch: /Found untracked files./ },
    { desc: `should do nothing and emit warning if there are uncommitted changes.`,
      setup: (setupConfig) => shell.exec(`cd ${setupConfig.localRepoCheckout} && echo 'hey' >> README.md`, execOpts),
      errMatch: /Found uncommitted changes./ },
    { desc: `should do nothing and emit warning if there are un-pushed changes.`,
      setup: (setupConfig) => shell.exec(`cd ${setupConfig.localRepoCheckout} && ( echo 'hey' >> README.md && git add README.md && git commit --quiet -m "test commit" )`, execOpts),
      errMatch: /Not all changes have been pushed to master./ },
  ]

  closeFailureTests.forEach(testConfig => {
    test(testConfig.desc, () => {
      console.error = jest.fn() // supresses err echo from shelljs
      const setupResult = testConfig.setup(setupConfig)
      expect(setupResult.stderr).toEqual('')
      expect(setupResult.code).toEqual(0)

      let result = shell.exec(`cd ${setupConfig.localRepoCheckout} && HOME=${setupConfig.home} ${testing.LIQ} projects close`, execOpts)
      expect(result.stderr).toMatch(testConfig.errMatch, "Bash output\n" + result.stderr)
      expect(result.stdout).toEqual('')
      expect(result.code).toEqual(1)

      result = shell.exec(`cd ${setupConfig.localRepoCheckout} && HOME=${setupConfig.home} ${testing.LIQ} projects close @liquid-labs/lc-entities-model`, execOpts)
      expect(result.stderr).toMatch(testConfig.errMatch)
      expect(result.stdout).toEqual('')
      expect(result.code).toEqual(1)
    })
  })

  test(`should remove current project when no changes present`, () => {
    // console.error = jest.fn() // supresses err echo from shelljs
    const expectedOutput = /^Removed project '@liquid-labs\/lc-entities-model'/
    const result = shell.exec(`cd ${setupConfig.localRepoCheckout} && HOME=${setupConfig.home} ${testing.LIQ} projects close`, execOpts)
    expect(result.stderr).toEqual('')
    expect(result.stdout).toMatch(expectedOutput)
    expect(result.code).toEqual(0)
    expect(shell.ls(`${setupConfig.playground}/liquid_labs`)).toHaveLength(0)
  })

  test(`should remove specified project when no changes present`, () => {
    console.error = jest.fn() // supresses err echo from shelljs
    const expectedOutput = /^Removed project '@liquid-labs\/lc-entities-model'/
    const result = shell.exec(`HOME=${setupConfig.home} ${testing.LIQ} projects close @liquid-labs/lc-entities-model`, execOpts)
    expect(result.stderr).toEqual('')
    expect(result.stdout).toMatch(expectedOutput)
    expect(result.code).toEqual(0)
    expect(shell.ls(`${setupConfig.playground}/liquid_labs`)).toHaveLength(0)
  })
})
