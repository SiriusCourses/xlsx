{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE DeriveGeneric #-}
module Codec.Xlsx.Types.Internal.SharedStringTable (
    -- * Main types
    SharedStringTable(..)
  , sstConstruct
  , sstLookupText
  , sstLookupRich
  , sstItem
  , sstEmpty
  ) where

#ifdef USE_MICROLENS
import Lens.Micro
#else
import Control.Lens hiding ((<.>), element, views)
#endif
import Control.Monad
import qualified Data.Map as Map
import Data.Maybe (mapMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import Data.Vector (Vector)
import qualified Data.Vector as V
import GHC.Generics (Generic)
import Numeric.Search.Range (searchFromTo)
import Safe (fromJustNote)
import Text.XML
import Text.XML.Cursor

import Codec.Xlsx.Parser.Internal
import Codec.Xlsx.Types
import Codec.Xlsx.Writer.Internal

-- | Shared string table
--
-- A workbook can contain thousands of cells containing string (non-numeric)
-- data. Furthermore this data is very likely to be repeated across many rows or
-- columns. The goal of implementing a single string table that is shared across
-- the workbook is to improve performance in opening and saving the file by only
-- reading and writing the repetitive information once.
--
-- Relevant parts of the EMCA standard (2nd edition, part 1,
-- <https://ecma-international.org/publications-and-standards/standards/ecma-376/>),
-- page numbers refer to the page in the PDF rather than the page number as
-- printed on the page):
--
-- * Section 18.4, "Shared String Table" (p. 1712)
--   in particular subsection 18.4.9, "sst (Shared String Table)" (p. 1726)
--
-- TODO: The @extLst@ child element is currently unsupported.
newtype SharedStringTable = SharedStringTable {
    sstTable :: Vector XlsxText
  }
  deriving (Eq, Ord, Show, Generic)

sstEmpty :: SharedStringTable
sstEmpty = SharedStringTable V.empty

{-------------------------------------------------------------------------------
  Rendering
-------------------------------------------------------------------------------}

instance ToDocument SharedStringTable where
  toDocument = documentFromElement "Shared string table generated by xlsx"
             . toElement "sst"

-- | See @CT_Sst@, p. 3902.
--
-- TODO: The @count@ and @uniqCount@ attributes are currently unsupported.
instance ToElement SharedStringTable where
  toElement nm SharedStringTable{..} = Element {
      elementName       = nm
    , elementAttributes = Map.empty
    , elementNodes      = map (NodeElement . toElement "si")
                        $ V.toList sstTable
    }

{-------------------------------------------------------------------------------
  Parsing
-------------------------------------------------------------------------------}

-- | See @CT_Sst@, p. 3902
--
-- The optional attributes @count@ and @uniqCount@ are being ignored at least currently
instance FromCursor SharedStringTable where
  fromCursor cur = do
    let
      items = cur $/ element (n_ "si") >=> fromCursor
    return (SharedStringTable (V.fromList items))

{-------------------------------------------------------------------------------
  Extract shared strings
-------------------------------------------------------------------------------}

-- | Construct the 'SharedStringsTable' from an existing document
sstConstruct :: [Worksheet] -> SharedStringTable
sstConstruct =
    SharedStringTable . V.fromList . uniq . concatMap goSheet
  where
    goSheet :: Worksheet -> [XlsxText]
    goSheet = mapMaybe (_cellValue >=> sstEntry) . Map.elems . _wsCells

    sstEntry :: CellValue -> Maybe XlsxText
    sstEntry (CellText text) = Just $ XlsxText (cleanText text)
    sstEntry (CellRich rich) = Just $ XlsxRichText (rich & traverse.richTextRunText %~ cleanText)
    sstEntry _               = Nothing

    uniq :: Ord a => [a] -> [a]
    uniq = Set.elems . Set.fromList

sstLookupText :: SharedStringTable -> Text -> Int
sstLookupText sst = sstLookup sst . XlsxText

sstLookupRich :: SharedStringTable -> [RichTextRun] -> Int
sstLookupRich sst = sstLookup sst . XlsxRichText

-- | Internal generalization used by 'sstLookupText' and 'sstLookupRich'
sstLookup :: SharedStringTable -> XlsxText -> Int
sstLookup SharedStringTable{sstTable = shared} si =
    fromJustNote ("SST entry for " ++ show si ++ " not found") $
    searchFromTo (\p -> shared V.! p >= si) 0 (V.length shared - 1)

sstItem :: SharedStringTable -> Int -> Maybe XlsxText
sstItem (SharedStringTable shared) = (V.!?) shared
