const path = require("path");
const glob = require("glob");
const MiniCssExtractPlugin = require("mini-css-extract-plugin");
const TerserPlugin = require("terser-webpack-plugin");
const CssMinimizerPlugin = require("css-minimizer-webpack-plugin");
const CopyWebpackPlugin = require("copy-webpack-plugin");

module.exports = (env, options) => ({
  cache: true,
  optimization: {
    minimizer: [
      new TerserPlugin(),
      new CssMinimizerPlugin(),
    ],
  },
  entry: {
    "./js/app.js": glob.sync("./vendor/**/*.js").concat(["./js/app.js"]),
  },
  output: {
    filename: "app.js",
    path: path.resolve(__dirname, "../priv/static/js"),
  },
  module: {
    rules: [
      {
        test: /\.s?css$/,
        use: [MiniCssExtractPlugin.loader, "css-loader", "sass-loader"],
      },
    ],
  },
  plugins: [
    new MiniCssExtractPlugin({ filename: "../css/app.css" }),
    new CopyWebpackPlugin({
      patterns: [
        { from: "static/", to: "../" }
      ]
    }),
  ],
});
