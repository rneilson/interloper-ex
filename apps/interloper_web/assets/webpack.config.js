const path = require('path');
const glob = require('glob');
const webpack = require('webpack');
const MiniCssExtractPlugin = require('mini-css-extract-plugin');
const UglifyJsPlugin = require('uglifyjs-webpack-plugin');
const OptimizeCSSAssetsPlugin = require('optimize-css-assets-webpack-plugin');
const CopyWebpackPlugin = require('copy-webpack-plugin');

module.exports = (env, options) => ({
  devtool: 'source-map',
  optimization: {
    // minimize: true,
    minimizer: [
      new UglifyJsPlugin({
        cache: true,
        parallel: true,
        // sourceMap: false,
        sourceMap: true,
        uglifyOptions: {
          comments: 'some',
        },
      }),
      new OptimizeCSSAssetsPlugin({})
    ]
  },
  entry: {
      './js/app.js': ['./js/app.js'].concat(glob.sync('./vendor/**/*.js'))
  },
  output: {
    filename: 'app.js',
    path: path.resolve(__dirname, '../priv/static/js')
  },
  module: {
    rules: [
      {
        test: /\.js$/,
        // exclude: /node_modules/,
        use: ['source-map-loader'],
        enforce: 'pre',
        // use: {
        //   loader: 'babel-loader'
        // }
      },
      {
        test: /\.css$/,
        use: [MiniCssExtractPlugin.loader, 'css-loader']
      }
    ]
  },
  plugins: [
    // new webpack.ProvidePlugin({
    //   Stimulus: path.resolve(__dirname, 'node_modules/stimulus/dist/stimulus.umd.js'),
    // }),
    new MiniCssExtractPlugin({ filename: '../css/app.css' }),
    new CopyWebpackPlugin([{ from: 'static/', to: '../' }])
  ]
});
