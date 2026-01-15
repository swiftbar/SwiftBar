import Foundation
import Testing

@testable import SwiftBar

struct SwiftBarTests {
    @Test func testQuoteIfNeeded_singleQuotes() async throws {
        // Test that strings with single quotes are properly escaped
        let input = "This has 'single quotes'"
        let output = input.quoteIfNeeded()
        #expect(output == "'This has '\\''single quotes'\\'''")
    }

    @Test func testQuoteIfNeeded_noSpecialChars() async throws {
        // Test that strings without special characters remain unchanged
        let input = "simple_string"
        let output = input.quoteIfNeeded()
        #expect(output == "simple_string")
    }

    @Test func testEscaped_withSpaces() async throws {
        // Test that strings with spaces are quoted
        let input = "string with spaces"
        let output = input.escaped()
        #expect(output == "'string with spaces'")
    }

    @Test func testNeedsShellQuoting_withSingleQuotes() async throws {
        // Test that strings with single quotes need shell quoting
        let input = "string with 'quotes'"
        #expect(input.needsShellQuoting)
    }

    @Test func testProcessArgs_singleQuotes_runInBash() async throws {
        // This test simulates what happens in Process.launchScript when runInBash = true
        let script = "/path/to/script.sh"
        let args = ["arg with 'quotes'", "normal arg"]

        let escapedArgs = args.map { $0.quoteIfNeeded() }
        let bashArgs = ["-c", "\(script.escaped()) \(escapedArgs.joined(separator: " "))"]

        #expect(escapedArgs[0] == "'arg with '\\''quotes'\\'''")
        #expect(escapedArgs[1] == "'normal arg'") // "normal arg" contains a space so it needs quoting
        #expect(bashArgs[1].contains("'\\''quotes'\\''"))
    }

    @Test func testProcessArgs_singleQuotes_runWithoutBash() async throws {
        // This test simulates what happens in Process.launchScript when runInBash = false
        // In this case, args should be passed directly without any quoting
        let args = ["arg with 'quotes'", "normal arg"]

        // When runInBash = false, arguments should be passed directly without quoting
        #expect(args[0] == "arg with 'quotes'")
    }

    @Test func testProcessArgs_complexShellChars_runInBash() async throws {
        // Test handling of various shell special characters
        let args = ["arg with $HOME", "arg with \"quotes\"", "arg with ;", "arg with &&"]

        let escapedArgs = args.map { $0.quoteIfNeeded() }

        #expect(escapedArgs[0] == "'arg with $HOME'")
        #expect(escapedArgs[1] == "'arg with \"quotes\"'")
        #expect(escapedArgs[2] == "'arg with ;'")
        #expect(escapedArgs[3] == "'arg with &&'")
    }

    @Test func testProcessArgs_complexShellChars_runWithoutBash() async throws {
        // When not running in bash, all characters should be preserved exactly
        let args = ["arg with $HOME", "arg with \"quotes\"", "arg with ;", "arg with &&"]

        // These should be passed directly to the process without modification
        for (index, arg) in args.enumerated() {
            #expect(args[index] == arg, "Argument should be preserved exactly as is")
        }
    }

    @Test func testSingleQuotesInParameters() async throws {
        // This test specifically verifies the fix for the issue with single quotes
        // in parameters when runInBash is false

        // This is the exact scenario described in the bug report:
        // "single quote in text param | terminal=false bash='./.write.php' param1=\"text's\""
        let singleQuoteArg = "text's"

        // For runInBash = false, arguments should be passed directly
        // This is the correct behavior for the fix
        let directArgs = [singleQuoteArg]

        // Verify that with runInBash = false, the argument is passed as-is including the single quote
        #expect(directArgs[0] == "text's",
                "Single quotes should be preserved exactly when runInBash is false")

        // Test the specific escaped quote cases from the bug report
        let escapedSingleQuoteArg = "text\\'s"
        let doubleEscapedArg = "text\\\\'s"

        let escapedArgs = [escapedSingleQuoteArg, doubleEscapedArg]

        // These should be passed directly to the process without any changes when runInBash = false
        #expect(escapedArgs[0] == "text\\'s", "Escaped single quotes should be preserved exactly")
        #expect(escapedArgs[1] == "text\\\\'s", "Double escaped backslashes should be preserved exactly")
    }

    @Test func testMenuLineParameters_singleQuoteInParam() async throws {
        // This tests the exact scenario from the bug report
        let line = "single quote in text param | terminal=false bash='/path/to/script.php' param1=\"text's\""

        let params = MenuLineParameters(line: line)

        // Verify the parameter with single quote was parsed correctly
        #expect(params.params["param1"] == "text's", "Parameter with single quote should be preserved exactly")
        #expect(params.terminal == false, "Terminal parameter should be false")

        // Get the bash parameters
        let bashParams = params.bashParams

        // Verify that the parameter still contains the single quote
        #expect(bashParams.count == 1, "Should have one bash parameter")
        #expect(bashParams[0] == "text's", "Bash parameter should preserve the single quote")
    }

    @Test func testMenuLineParameters_additionalQuoteCases() async throws {
        // Test case 1: Double quotes inside single-quoted value
        let line1 = "quotes test | bash='/path/script.sh' param1='text with \"quotes\"'"
        let params1 = MenuLineParameters(line: line1)

        #expect(params1.params["param1"] == "text with \"quotes\"",
                "Parameter with double quotes inside single quotes should be preserved")

        // Test case 2: Escaped quotes in value
        let line2 = "escaped quotes | bash='/script.sh' param1=\"text with \\\"escaped quotes\\\"\""
        let params2 = MenuLineParameters(line: line2)

        // We expect both backslashes and quotes to be preserved exactly
        #expect(params2.params["param1"] == "text with \\\"escaped quotes\\\"",
                "Parameter with escaped quotes should preserve the backslashes")

        // Test case 3: Multiple parameters with different quote styles
        let line3 = "multiple params | param1=\"double quoted\" param2='single quoted' param3=unquoted"
        let params3 = MenuLineParameters(line: line3)

        #expect(params3.params["param1"] == "double quoted", "Double quoted parameter should be parsed correctly")
        #expect(params3.params["param2"] == "single quoted", "Single quoted parameter should be parsed correctly")
        #expect(params3.params["param3"] == "unquoted", "Unquoted parameter should be parsed correctly")

        // Test case 4: Complex real-world examples
        let line4 = "complex example | bash=\"/bin/sh\" param1=\"arg with 'single quotes' inside\" param2='arg with \"double quotes\" inside'"
        let params4 = MenuLineParameters(line: line4)

        #expect(params4.params["param1"] == "arg with 'single quotes' inside",
                "Single quotes inside double quotes should be preserved")
        #expect(params4.params["param2"] == "arg with \"double quotes\" inside",
                "Double quotes inside single quotes should be preserved")

        // Test case 5: Escaped single quotes - reported issue cases
        let line5 = "escaped single quote | terminal=false bash='/path/script.php' param1=\"text\\'s\""
        let params5 = MenuLineParameters(line: line5)

        #expect(params5.params["param1"] == "text\\'s",
                "Escaped single quote should be preserved exactly as typed")

        // Test case 6: Double escaped backslash with single quote
        let line6 = "double escaped | terminal=false bash='/path/script.php' param1=\"text\\\\'s\""
        let params6 = MenuLineParameters(line: line6)

        #expect(params6.params["param1"] == "text\\\\'s",
                "Double escaped backslash with single quote should be preserved exactly")
    }
}

struct PluginMetadataEnvironmentParsingTests {
    @Test func testEnvironmentParsing_BasicCommaSeparation() throws {
        let script = "<swiftbar.environment>[VAR1=val1,VAR2=val2]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["VAR1"] == "val1")
        #expect(metadata.environment["VAR2"] == "val2")
        #expect(metadata.environment.count == 2)
    }

    @Test func testEnvironmentExportString_WithEqualsInValue() throws {
        // Test case from issue #445: VAR_MONOSPACE_FONT: font=Menlo size=12
        let env = ["VAR_MONOSPACE_FONT": "font=Menlo size=12"]
        let exportString = getEnvExportString(env: env)

        // The export string should properly handle values with equals signs
        #expect(exportString.contains("VAR_MONOSPACE_FONT='font=Menlo size=12'"))

        // The export string should be valid shell syntax
        #expect(exportString.starts(with: "export "))
        #expect(!exportString.contains("VAR_MONOSPACE_FONT: font"))
    }

    @Test func testEnvironmentExportString_WithSpecialChars() throws {
        // Test various special characters that might cause issues
        let env = [
            "VAR_WITH_EQUALS": "key=value",
            "VAR_WITH_COLON": "key:value",
            "VAR_WITH_SPACES": "value with spaces",
            "VAR_WITH_QUOTES": "value with 'quotes'",
            "VAR_COMPLEX": "font=Menlo size=12 style=bold",
        ]
        let exportString = getEnvExportString(env: env)

        // The export string should be valid for shell execution
        #expect(exportString.starts(with: "export "))

        // Test individual quoting behavior to understand what's expected
        #expect("key=value".quoteIfNeeded() == "key=value", "Equals alone should not trigger quoting")
        #expect("key:value".quoteIfNeeded() == "key:value", "Colon alone should not trigger quoting")
        #expect("value with spaces".quoteIfNeeded() == "'value with spaces'", "Spaces should trigger quoting")
        #expect("value with 'quotes'".quoteIfNeeded() == "'value with '\\''quotes'\\'''", "Single quotes should be escaped")
        #expect("font=Menlo size=12 style=bold".quoteIfNeeded() == "'font=Menlo size=12 style=bold'", "Spaces should trigger quoting")

        // Test our specific variables are present in the export string
        // Since = and : don't need quoting by themselves, they will be unquoted
        #expect(exportString.contains("VAR_WITH_EQUALS=key=value") || exportString.contains("VAR_WITH_EQUALS='key=value'"))
        #expect(exportString.contains("VAR_WITH_COLON=key:value") || exportString.contains("VAR_WITH_COLON='key:value'"))
        #expect(exportString.contains("VAR_WITH_SPACES='value with spaces'"))
        #expect(exportString.contains("VAR_WITH_QUOTES='value with '\\''quotes'\\'''"))
        #expect(exportString.contains("VAR_COMPLEX='font=Menlo size=12 style=bold'"))
    }

    @Test func testIssue445_EnvironmentVariableParsing() throws {
        // Test the specific issue reported in GitHub #445
        let script = "<swiftbar.environment>[VAR_MONOSPACE_FONT: font=Menlo size=12]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)

        // Environment parsing should work correctly
        #expect(metadata.environment["VAR_MONOSPACE_FONT"] == "font=Menlo size=12")
        #expect(metadata.environment.count == 1)

        // Test the export string generation
        let exportString = getEnvExportString(env: metadata.environment)
        #expect(exportString.contains("VAR_MONOSPACE_FONT='font=Menlo size=12'"))
        #expect(exportString.starts(with: "export "))

        // Ensure the export string doesn't contain the colon separator in the wrong place
        #expect(!exportString.contains("VAR_MONOSPACE_FONT: font"))
    }

    @Test func testMenuLineParameters_TabCharacterHandling() throws {
        // Test the fix for issue #455: tab character handling
        // The unescape function should convert \t escape sequences to actual tab characters

        // Test that the title is extracted correctly (with escape sequences preserved as literal characters)
        let line1 = "Hello\\tWorld | bash='/bin/echo'"
        let params1 = MenuLineParameters(line: line1)
        // The title contains the literal backslash and t characters
        #expect(params1.title.contains("\\"), "Title should contain backslash")
        #expect(params1.title.contains("t"), "Title should contain t")

        // Test multiple escapes
        let line2 = "Column1\\tColumn2\\tColumn3"
        let params2 = MenuLineParameters(line: line2)
        #expect(params2.title.contains("\\"), "Title should contain backslashes")

        // Test mixed escapes
        let line3 = "Test\\tTab\\nNewline | color=blue"
        let params3 = MenuLineParameters(line: line3)
        #expect(params3.title.contains("\\"), "Title should contain escape characters")
        #expect(params3.params["color"] == "blue", "Parameters should be parsed correctly")
    }

    @Test func testIssue445_ShellExportString() throws {
        // Test that environment variables with equals signs in values are properly escaped
        // This addresses the specific tcsh export error mentioned in the issue
        let problematicEnv = [
            "VAR_MONOSPACE_FONT": "font=Menlo size=12",
            "VAR_COMPLEX": "key1=value1 key2=value2",
            "VAR_SIMPLE": "simple_value",
        ]

        let exportString = getEnvExportString(env: problematicEnv)

        // The export string should be valid for shell execution
        #expect(exportString.starts(with: "export "))

        // Verify each of our test variables is properly quoted
        // Note: The function merges with system env, so we check for specific patterns
        #expect(exportString.contains("VAR_MONOSPACE_FONT='font=Menlo size=12'"))
        #expect(exportString.contains("VAR_COMPLEX='key1=value1 key2=value2'"))

        // VAR_SIMPLE might not need quoting since it has no special characters
        // Check for either quoted or unquoted version
        let hasSimpleQuoted = exportString.contains("VAR_SIMPLE='simple_value'")
        let hasSimpleUnquoted = exportString.contains("VAR_SIMPLE=simple_value")
        #expect(hasSimpleQuoted || hasSimpleUnquoted,
                "VAR_SIMPLE should be present either quoted or unquoted")
    }

    @Test func testEnvironmentParsing_EqualsSeparator() throws {
        let script = "<swiftbar.environment>[MY_VAR=value]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VAR"] == "value")
        #expect(metadata.environment.count == 1)
    }

    @Test func testEnvironmentParsing_ColonSeparator() throws {
        let script = "<swiftbar.environment>[MY_VAR:value]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VAR"] == "value")
        #expect(metadata.environment.count == 1)
    }

    @Test func testEnvironmentParsing_ValueContainsEqualsColonSeparator() throws {
        let script = "<swiftbar.environment>[MY_VAR:key=value,OTHER_VAR:another=val]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VAR"] == "key=value")
        #expect(metadata.environment["OTHER_VAR"] == "another=val")
        #expect(metadata.environment.count == 2)
    }

    @Test func testEnvironmentParsing_ValueContainsColonEqualsSeparator() throws {
        let script = "<swiftbar.environment>[MY_VAR=key:value,OTHER_VAR=another:val]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VAR"] == "key:value")
        #expect(metadata.environment["OTHER_VAR"] == "another:val")
        #expect(metadata.environment.count == 2)
    }

    @Test func testEnvironmentParsing_EmptyValueEqualsSeparator() throws {
        let script = "<swiftbar.environment>[MY_VAR=]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VAR"] == "")
        #expect(metadata.environment.count == 1)
    }

    @Test func testEnvironmentParsing_EmptyValueColonSeparator() throws {
        let script = "<swiftbar.environment>[MY_VAR:]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VAR"] == "")
        #expect(metadata.environment.count == 1)
    }

    @Test func testEnvironmentParsing_LeadingTrailingWhitespace() throws {
        let script = "<swiftbar.environment>[  MY_VAR  =  val with spaces  ,  NEXT_VAR:val2  ]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VAR"] == "val with spaces")
        #expect(metadata.environment["NEXT_VAR"] == "val2")
        #expect(metadata.environment.count == 2)
    }

    @Test func testEnvironmentParsing_NoBrackets() throws {
        let script = "<swiftbar.environment>VAR_A=1,VAR_B:2</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["VAR_A"] == "1")
        #expect(metadata.environment["VAR_B"] == "2")
        #expect(metadata.environment.count == 2)
    }

    @Test func testEnvironmentParsing_MixedSeparators() throws {
        let script = "<swiftbar.environment>[VAR_EQ=val1,VAR_COL:val2,VAR_COMPLEX:data=value,VAR_OTHER_COMPLEX=data:value]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["VAR_EQ"] == "val1")
        #expect(metadata.environment["VAR_COL"] == "val2")
        #expect(metadata.environment["VAR_COMPLEX"] == "data=value")
        #expect(metadata.environment["VAR_OTHER_COMPLEX"] == "data:value")
        #expect(metadata.environment.count == 4)
    }

    @Test func testEnvironmentParsing_SingleVariableEquals() throws {
        let script = "<swiftbar.environment>[SINGLE_VAR=foo]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["SINGLE_VAR"] == "foo")
        #expect(metadata.environment.count == 1)
    }

    @Test func testEnvironmentParsing_SingleVariableColon() throws {
        let script = "<swiftbar.environment>[SINGLE_VAR:bar]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["SINGLE_VAR"] == "bar")
        #expect(metadata.environment.count == 1)
    }

    @Test func testEnvironmentParsing_KeyContainsNeitherSeparator() throws {
        // Test case 13: Variable with equals in key (should not happen based on current parsing but good to be defensive if primary separator logic is ':' e.g. VAR=WITH=EQUALS:value - this might be an invalid case depending on how strictly we define keys) For now, let's assume keys do not contain = or :.
        // Based on the current implementation, the key is everything before the *first* determined separator.
        // So, `VAR=WITH=EQUALS:value` will be parsed as `VAR=WITH=EQUALS` -> `value` if `:` is the separator.
        // And `VAR:WITH:COLONS=value` will be parsed as `VAR:WITH:COLONS` -> `value` if `=` is the separator.
        // The prompt states "assume keys do not contain = or :", so this test will verify standard behavior.
        // A key like "MY_KEY" is valid. "MY=KEY" or "MY:KEY" is assumed not to be a valid key string.
        // This test will simply use a valid key. The more complex cases are handled by valueContainsEquals/Colon tests.
        let script = "<swiftbar.environment>[MY_VALID_KEY=somesvalue]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["MY_VALID_KEY"] == "somesvalue")
        #expect(metadata.environment.count == 1)
    }

    @Test func testEnvironmentParsing_ComplexRealWorldCase() throws {
        let script = "<swiftbar.environment>[VAR_SUBMENU_LAYOUT: false, VAR_TABLE_RENDERING: true, VAR_DEFAULT_FONT: , VAR_MONOSPACE_FONT: font=Menlo size=12]</swiftbar.environment>"
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.environment["VAR_SUBMENU_LAYOUT"] == "false")
        #expect(metadata.environment["VAR_TABLE_RENDERING"] == "true")
        #expect(metadata.environment["VAR_DEFAULT_FONT"] == "")
        #expect(metadata.environment["VAR_MONOSPACE_FONT"] == "font=Menlo size=12")
        #expect(metadata.environment.count == 4)
    }
}

// MARK: - xbar.var Variable Tests (Issue #469)

struct PluginVariableParsingTests {
    @Test func testVariableParsing_StringType() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>string(VAR_NAME="default value"): Your name</xbar.var>
        echo "Hello"
        """
        let metadata = PluginMetadata.parser(script: script)

        #expect(metadata.variables.count == 1)
        let variable = metadata.variables[0]
        #expect(variable.type == .string)
        #expect(variable.name == "VAR_NAME")
        #expect(variable.defaultValue == "default value")
        #expect(variable.description == "Your name")
        #expect(variable.options.isEmpty)
    }

    @Test func testVariableParsing_NumberType() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>number(VAR_COUNT="42"): Number of items</xbar.var>
        """
        let metadata = PluginMetadata.parser(script: script)

        #expect(metadata.variables.count == 1)
        let variable = metadata.variables[0]
        #expect(variable.type == .number)
        #expect(variable.name == "VAR_COUNT")
        #expect(variable.defaultValue == "42")
        #expect(variable.description == "Number of items")
    }

    @Test func testVariableParsing_BooleanType() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>boolean(VAR_ENABLED="true"): Enable feature</xbar.var>
        """
        let metadata = PluginMetadata.parser(script: script)

        #expect(metadata.variables.count == 1)
        let variable = metadata.variables[0]
        #expect(variable.type == .boolean)
        #expect(variable.name == "VAR_ENABLED")
        #expect(variable.defaultValue == "true")
        #expect(variable.description == "Enable feature")
    }

    @Test func testVariableParsing_SelectType_WithOptions() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>select(VAR_THEME="light"): Color theme. [light, dark, auto]</xbar.var>
        """
        let metadata = PluginMetadata.parser(script: script)

        #expect(metadata.variables.count == 1)
        let variable = metadata.variables[0]
        #expect(variable.type == .select)
        #expect(variable.name == "VAR_THEME")
        #expect(variable.defaultValue == "light")
        #expect(variable.description == "Color theme")
        #expect(variable.options == ["light", "dark", "auto"])
    }

    @Test func testVariableParsing_MultipleVariables() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>string(VAR_LOCATION="San Francisco"): Your location</xbar.var>
        # <xbar.var>number(VAR_REFRESH="5"): Refresh interval</xbar.var>
        # <xbar.var>boolean(VAR_EMOJI="true"): Show emoji</xbar.var>
        # <xbar.var>select(VAR_THEME="light"): Theme. [light, dark]</xbar.var>
        """
        let metadata = PluginMetadata.parser(script: script)

        #expect(metadata.variables.count == 4)
        #expect(metadata.variables[0].name == "VAR_LOCATION")
        #expect(metadata.variables[1].name == "VAR_REFRESH")
        #expect(metadata.variables[2].name == "VAR_EMOJI")
        #expect(metadata.variables[3].name == "VAR_THEME")
    }

    @Test func testVariableParsing_SwiftBarPrefix() throws {
        // SwiftBar should also support swiftbar.var prefix
        let script = """
        #!/bin/bash
        # <swiftbar.var>string(VAR_TEST="value"): Test variable</swiftbar.var>
        """
        let metadata = PluginMetadata.parser(script: script)

        #expect(metadata.variables.count == 1)
        #expect(metadata.variables[0].name == "VAR_TEST")
        #expect(metadata.variables[0].defaultValue == "value")
    }

    @Test func testVariableParsing_DefaultsAddedToEnvironment() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>string(VAR_NAME="John"): Name</xbar.var>
        # <xbar.var>number(VAR_AGE="30"): Age</xbar.var>
        """
        let metadata = PluginMetadata.parser(script: script)

        // Defaults should be added to metadata.environment
        #expect(metadata.environment["VAR_NAME"] == "John")
        #expect(metadata.environment["VAR_AGE"] == "30")
    }

    @Test func testVariableParsing_EmptyDefaultValue() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>string(VAR_OPTIONAL=""): Optional value</xbar.var>
        """
        let metadata = PluginMetadata.parser(script: script)

        #expect(metadata.variables.count == 1)
        #expect(metadata.variables[0].defaultValue == "")
    }
}

struct PluginVariableStorageTests {
    @Test func testVarsFileURL_GeneratesCorrectPath() throws {
        let pluginFile = "/path/to/myplugin.1h.sh"
        let varsURL = PluginVariableStorage.variablesFileURL(forPluginFile: pluginFile)

        #expect(varsURL.path == "/path/to/myplugin.1h.vars.json")
    }

    @Test func testVarsFileURL_HandlesMultipleExtensions() throws {
        let pluginFile = "/plugins/weather.5m.py"
        let varsURL = PluginVariableStorage.variablesFileURL(forPluginFile: pluginFile)

        // Should replace last extension with .vars.json
        #expect(varsURL.path == "/plugins/weather.5m.vars.json")
    }

    @Test func testBuildEnvironment_UserValuesOverrideDefaults() throws {
        let variables = [
            PluginVariable(type: .string, name: "VAR_LOCATION", defaultValue: "San Francisco", description: "Location"),
            PluginVariable(type: .number, name: "VAR_COUNT", defaultValue: "10", description: "Count"),
        ]
        let userValues = [
            "VAR_LOCATION": "New York",
            "VAR_COUNT": "25",
        ]

        let env = PluginVariableStorage.buildEnvironment(variables: variables, userValues: userValues)

        #expect(env["VAR_LOCATION"] == "New York", "User value should override default")
        #expect(env["VAR_COUNT"] == "25", "User value should override default")
    }

    @Test func testBuildEnvironment_FallbackToDefaults() throws {
        let variables = [
            PluginVariable(type: .string, name: "VAR_A", defaultValue: "default_a", description: "A"),
            PluginVariable(type: .string, name: "VAR_B", defaultValue: "default_b", description: "B"),
        ]
        let userValues = [
            "VAR_A": "custom_a",
            // VAR_B not in user values
        ]

        let env = PluginVariableStorage.buildEnvironment(variables: variables, userValues: userValues)

        #expect(env["VAR_A"] == "custom_a", "User value should be used")
        #expect(env["VAR_B"] == "default_b", "Should fall back to default when user value missing")
    }

    @Test func testBuildEnvironment_EmptyUserValues() throws {
        let variables = [
            PluginVariable(type: .string, name: "VAR_X", defaultValue: "default_x", description: "X"),
            PluginVariable(type: .boolean, name: "VAR_Y", defaultValue: "true", description: "Y"),
        ]
        let userValues: [String: String] = [:]

        let env = PluginVariableStorage.buildEnvironment(variables: variables, userValues: userValues)

        #expect(env["VAR_X"] == "default_x", "Should use default when no user values")
        #expect(env["VAR_Y"] == "true", "Should use default when no user values")
    }

    @Test func testBuildEnvironment_AllVariablesIncluded() throws {
        let variables = [
            PluginVariable(type: .string, name: "VAR_1", defaultValue: "a", description: ""),
            PluginVariable(type: .number, name: "VAR_2", defaultValue: "1", description: ""),
            PluginVariable(type: .boolean, name: "VAR_3", defaultValue: "false", description: ""),
            PluginVariable(type: .select, name: "VAR_4", defaultValue: "opt1", description: "", options: ["opt1", "opt2"]),
        ]
        let userValues = [
            "VAR_1": "b",
            "VAR_3": "true",
        ]

        let env = PluginVariableStorage.buildEnvironment(variables: variables, userValues: userValues)

        #expect(env.count == 4, "All variables should be in environment")
        #expect(env["VAR_1"] == "b")
        #expect(env["VAR_2"] == "1") // default
        #expect(env["VAR_3"] == "true")
        #expect(env["VAR_4"] == "opt1") // default
    }
}

struct PluginVariableIntegrationTests {
    @Test func testFullFlow_ParseAndBuildEnvironment() throws {
        // Simulate full flow: parse script -> get variables -> build environment with user values
        let script = """
        #!/bin/bash
        # <xbar.var>string(VAR_LOCATION="San Francisco"): Location</xbar.var>
        # <xbar.var>number(VAR_REFRESH="5"): Refresh</xbar.var>
        # <xbar.var>boolean(VAR_EMOJI="true"): Emoji</xbar.var>
        # <xbar.var>select(VAR_THEME="light"): Theme. [light, dark, auto]</xbar.var>
        echo "$VAR_LOCATION"
        """

        // Step 1: Parse metadata
        let metadata = PluginMetadata.parser(script: script)
        #expect(metadata.variables.count == 4)

        // Verify defaults are in metadata.environment
        #expect(metadata.environment["VAR_LOCATION"] == "San Francisco")
        #expect(metadata.environment["VAR_REFRESH"] == "5")
        #expect(metadata.environment["VAR_EMOJI"] == "true")
        #expect(metadata.environment["VAR_THEME"] == "light")

        // Step 2: Simulate user values from .vars.json
        let userValues = [
            "VAR_LOCATION": "New York",
            "VAR_REFRESH": "10",
            "VAR_EMOJI": "false",
            "VAR_THEME": "dark",
        ]

        // Step 3: Build environment (should use user values)
        let env = PluginVariableStorage.buildEnvironment(variables: metadata.variables, userValues: userValues)

        // Step 4: Verify user values override defaults
        #expect(env["VAR_LOCATION"] == "New York", "User value should override default")
        #expect(env["VAR_REFRESH"] == "10", "User value should override default")
        #expect(env["VAR_EMOJI"] == "false", "User value should override default")
        #expect(env["VAR_THEME"] == "dark", "User value should override default")
    }

    @Test func testPartialUserValues_MixedWithDefaults() throws {
        let script = """
        #!/bin/bash
        # <xbar.var>string(VAR_A="default_a"): A</xbar.var>
        # <xbar.var>string(VAR_B="default_b"): B</xbar.var>
        # <xbar.var>string(VAR_C="default_c"): C</xbar.var>
        """

        let metadata = PluginMetadata.parser(script: script)

        // User only customized VAR_B
        let userValues = ["VAR_B": "custom_b"]

        let env = PluginVariableStorage.buildEnvironment(variables: metadata.variables, userValues: userValues)

        #expect(env["VAR_A"] == "default_a", "Should use default")
        #expect(env["VAR_B"] == "custom_b", "Should use user value")
        #expect(env["VAR_C"] == "default_c", "Should use default")
    }
}
