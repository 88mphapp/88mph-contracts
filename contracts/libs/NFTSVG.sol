// SPDX-License-Identifier: MIT
///@notice Inspired by Uniswap-v3-periphery NFTSVG.sol
pragma solidity 0.8.4;

import "@openzeppelin/contracts/utils/Strings.sol";
import "base64-sol/base64.sol";
import "./HexStrings.sol";

library NFTSVG {
    using Strings for uint256;

    struct SVGParams {
        uint256 tokenId;
        string owner;
        string name;
        string symbol;
        string color0;
        string color1;
    }

    function generateSVG(SVGParams memory params)
        internal
        pure
        returns (string memory svg)
    {
        return
            string(
                abi.encodePacked(
                    generateSVGDefs(params),
                    generateSVGBackGround(params.tokenId, params.name),
                    generateSVGFigures(params),
                    "</svg>"
                )
            );
    }

    function generateSVGDefs(SVGParams memory params)
        private
        pure
        returns (string memory svg)
    {
        svg = string(
            abi.encodePacked(
                '<svg width="419" height="292" viewBox="0 0 419 292" fill="none" xmlns="http://www.w3.org/2000/svg"><defs><linearGradient id="g1" x1="0%" y1="50%" >',
                generateSVGColorPartOne(params),
                generateSVGColorPartTwo(params),
                "</linearGradient>",
                generateSVGFilter(
                    "filter0_d",
                    ["85.852", "212.189"],
                    ["238.557", "53.1563"],
                    "2"
                ),
                generateSVGFilter(
                    "filter1_d",
                    ["90.075", "103.557"],
                    ["228.372", "171.911"],
                    "6"
                ),
                '<linearGradient id="paint0_linear" x1="209.162" y1="291.796" x2="209.162" y2="1.0534" gradientUnits="userSpaceOnUse"><stop stop-color="#FFE600"/><stop offset="0.307292" stop-color="#FAAD14"/><stop offset="0.671875" stop-color="#F7169C"/><stop offset="1" stop-color="#3435F5"/></linearGradient>',
                generateSVGGradient(),
                "</defs>"
            )
        );
    }

    function generateSVGFigures(SVGParams memory params)
        private
        pure
        returns (string memory svg)
    {
        svg = string(
            abi.encodePacked(
                '<path fill-rule="evenodd" clip-rule="evenodd" d="M195.243 283.687C201.373 294.499 216.951 294.499 223.081 283.687L235.238 262.244H183.086L195.243 283.687ZM173.834 245.923L155.328 213.282H262.996L244.49 245.923H173.834ZM146.076 196.961H272.248L290.754 164.32H127.57L146.076 196.961ZM118.318 147.999L99.8123 115.358H318.512L300.006 147.999H118.318ZM90.5596 99.0369H327.764L349.634 60.4607H68.6896L90.5596 99.0369ZM59.437 44.1401L47.9572 23.8909C41.9102 13.2248 49.6149 0 61.876 0H356.448C368.709 0 376.414 13.2248 370.367 23.891L358.887 44.1401H59.437Z" fill="url(#paint0_linear)"/>',
                generateSVGText(params)
            )
        );
    }

    function generateSVGText(SVGParams memory params)
        private
        pure
        returns (string memory svg)
    {
        svg = string(
            abi.encodePacked(
                '<g fill="black" font-family="monospace" font-style="bold" font-weight="bolder" style="text-shadow:4px 4px #558ABB; text-align:center;">',
                '<text><tspan x="35" y="105" dx="20" font-size="25">',
                params.name,
                '</tspan><tspan x="35" y="165" dx="10" font-size="12" >',
                params.owner,
                '</tspan><tspan x="165" y="190" dx="10" font-size="12" >tokenId :',
                params.tokenId.toString(),
                "</tspan></text></g>"
            )
        );
    }

    function generateSVGFilter(
        string memory id,
        string[2] memory coordinates,
        string[2] memory size,
        string memory stdDeviation
    ) private pure returns (string memory svg) {
        string memory filterFragment =
            string(
                abi.encodePacked(
                    '<filter id="',
                    id,
                    '" x="',
                    coordinates[0],
                    '" y="',
                    coordinates[1],
                    '" width="',
                    size[0],
                    '" height="',
                    size[1],
                    '" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB">'
                )
            );
        svg = string(
            abi.encodePacked(
                filterFragment,
                '<feFlood flood-opacity="0" result="BackgroundImageFix"/><feColorMatrix in="SourceAlpha" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"/><feOffset dy="4"/><feGaussianBlur stdDeviation="',
                stdDeviation,
                '"/><feColorMatrix type="matrix" values="0 0 0 0 0.898039 0 0 0 0 0.129412 0 0 0 0 0.615686 0 0 0 0.5 0"/><feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow"/>',
                '<feBlend mode="normal" in="SourceGraphic" in2="effect1_dropShadow" result="shape"/></filter>'
            )
        );
    }

    function generateSVGGradient() private pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                generateSVGGradientEleOne("paint1_linear"),
                generateSVGGradientEleOne("paint2_linear"),
                generateSVGGradientEleOne("paint3_linear"),
                generateSVGGradientEleTwo("paint4_linear"),
                generateSVGGradientEleTwo("paint5_linear"),
                generateSVGGradientEleTwo("paint6_linear")
            )
        );
    }

    function generateSVGGradientEleOne(string memory id)
        private
        pure
        returns (string memory svg)
    {
        svg = string(
            abi.encodePacked(
                '<linearGradient id="',
                id,
                '" x1="212.356" y1="140" x2="248.856" y2="265.5" gradientUnits="userSpaceOnUse">',
                '<stop offset="0.223958" stop-color="#FF009D"/><stop offset="0.880208" stop-color="#3435F5"/></linearGradient>'
            )
        );
    }

    function generateSVGGradientEleTwo(string memory id)
        private
        pure
        returns (string memory svg)
    {
        svg = string(
            abi.encodePacked(
                '<linearGradient id="',
                id,
                '" x1="195.663" y1="154.629" x2="198.752" y2="249" gradientUnits="userSpaceOnUse">',
                '<stop stop-color="white"/><stop offset="1" stop-color="#F7169C"/></linearGradient>'
            )
        );
    }

    function generateSVGColorPartOne(SVGParams memory params)
        private
        pure
        returns (string memory svg)
    {
        string memory values0 =
            string(abi.encodePacked("#", params.color0, "; #", params.color1));
        string memory values1 =
            string(abi.encodePacked("#", params.color1, "; #", params.color0));
        svg = string(
            abi.encodePacked(
                '<stop offset="0%" stop-color="#',
                params.color0,
                '" ><animate id="a1" attributeName="stop-color" values="',
                values0,
                '" begin="0; a2.end" dur="3s" /><animate id="a2" attributeName="stop-color" values="',
                values1,
                '" begin="a1.end" dur="3s" /></stop>'
            )
        );
    }

    function generateSVGColorPartTwo(SVGParams memory params)
        private
        pure
        returns (string memory svg)
    {
        string memory values0 =
            string(abi.encodePacked("#", params.color0, "; #", params.color1));
        string memory values1 =
            string(abi.encodePacked("#", params.color1, "; #", params.color0));
        svg = string(
            abi.encodePacked(
                '<stop offset="100%" stop-color="#',
                params.color1,
                '" >',
                '<animate id="a3" attributeName="stop-color" values="',
                values1,
                '" begin="0; a4.end" dur="3s" /><animate id="a4" attributeName="stop-color" values="',
                values0,
                '" begin="a3.end" dur="3s" /></stop>'
            )
        );
    }

    function generateSVGBackGround(uint256 tokenId, string memory name)
        private
        pure
        returns (string memory svg)
    {
        if (isRare(tokenId, name)) {
            svg = string(
                abi.encodePacked(
                    '<rect id="r" x="0" y="0" width="419" height="512" ',
                    'fill="url(#g1)" />'
                )
            );
        } else {
            svg = string(
                abi.encodePacked(
                    '<rect id="r" x="0" y="0" width="419" height="512" ',
                    'fill="black" />'
                )
            );
        }
    }

    function isRare(uint256 tokenId, string memory name)
        internal
        pure
        returns (bool)
    {
        return uint256(keccak256(abi.encodePacked(tokenId, name))) > 5**tokenId;
    }
}
