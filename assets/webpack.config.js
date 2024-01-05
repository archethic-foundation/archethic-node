const CopyWebpackPlugin = require('copy-webpack-plugin');

module.exports = (env, options) => ({
    plugins: [
        new CopyWebpackPlugin([{ from: 'assets/css', to: 'css' }]),
        new CopyWebpackPlugin([{ from: 'assets/fonts', to: 'fonts' }])
    ]
});
