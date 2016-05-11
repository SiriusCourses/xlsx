{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wall #-}
module Codec.Xlsx.Writer.Internal (
    -- * Rendering documents
    ToDocument(..)
  , documentFromElement
    -- * Rendering elements
  , ToElement(..)
  , countedElementList
  , elementListSimple
  , elementContent
  , elementContentPreserved
  , elementValue
    -- * Rendering attributes
  , ToAttrVal(..)
  , (.=)
  , (.=?)
    -- * Dealing with namespaces
  , addNS
  , mainNamespace
  ) where

import Data.Text (Text)
import Data.String (fromString)
import Text.XML
import qualified Data.Map as Map

{-------------------------------------------------------------------------------
  Rendering documents
-------------------------------------------------------------------------------}

class ToDocument a where
  toDocument :: a -> Document

documentFromElement :: Text -> Element -> Document
documentFromElement comment e = Document {
      documentRoot     = addNS mainNamespace e
    , documentEpilogue = []
    , documentPrologue = Prologue {
          prologueBefore  = [MiscComment comment]
        , prologueDoctype = Nothing
        , prologueAfter   = []
        }
    }

{-------------------------------------------------------------------------------
  Rendering elements
-------------------------------------------------------------------------------}

class ToElement a where
  toElement :: Name -> a -> Element

countedElementList :: Name -> [Element] -> Element
countedElementList nm as = elementList0 nm as [ "count" .= length as ]

elementList0 :: Name -> [Element] -> [(Name, Text)] -> Element
elementList0 nm els attrs = Element {
      elementName       = nm
    , elementNodes      = map NodeElement els
    , elementAttributes = Map.fromList attrs
    }

elementListSimple :: Name -> [Element] -> Element
elementListSimple nm els = elementList0 nm els []

elementContent0 :: Name -> [(Name, Text)] -> Text -> Element
elementContent0 nm attrs txt = Element {
      elementName       = nm
    , elementAttributes = Map.fromList attrs
    , elementNodes      = [NodeContent txt]
    }

elementContent :: Name -> Text -> Element
elementContent nm txt = elementContent0 nm [] txt

elementContentPreserved :: Name -> Text -> Element
elementContentPreserved nm txt = elementContent0 nm [ preserveSpace ] txt
  where
    preserveSpace = (
        Name { nameLocalName = "space"
             , nameNamespace = Just "http://www.w3.org/XML/1998/namespace"
             , namePrefix    = Nothing
             }
      , "preserve"
      )

{-------------------------------------------------------------------------------
  Rendering attributes
-------------------------------------------------------------------------------}

class ToAttrVal a where
  toAttrVal :: a -> Text

instance ToAttrVal Text   where toAttrVal = id
instance ToAttrVal String where toAttrVal = fromString
instance ToAttrVal Int    where toAttrVal = fromString . show
instance ToAttrVal Double where toAttrVal = fromString . show

instance ToAttrVal Bool where
  toAttrVal True  = "true"
  toAttrVal False = "false"

elementValue :: ToAttrVal a => Name -> a -> Element
elementValue nm a = Element {
      elementName       = nm
    , elementAttributes = Map.fromList [ "val" .= a ]
    , elementNodes      = []
    }

(.=) :: ToAttrVal a => Name -> a -> (Name, Text)
nm .= a = (nm, toAttrVal a)

(.=?) :: ToAttrVal a => Name -> Maybe a -> Maybe (Name, Text)
_  .=? Nothing  = Nothing
nm .=? (Just a) = Just (nm .= a)

{-------------------------------------------------------------------------------
  Dealing with namespaces
-------------------------------------------------------------------------------}

-- | Set the namespace for the entire document
--
-- This follows the same policy that the rest of the xlsx package uses.
addNS :: Text -> Element -> Element
addNS ns Element{..} = Element{
      elementName       = goName elementName
    , elementAttributes = elementAttributes
    , elementNodes      = map goNode elementNodes
    }
  where
    goName :: Name -> Name
    goName n@Name{..} =
      case nameNamespace of
        Just _  -> n -- If a namespace was explicitly set, leave it
        Nothing -> Name{
            nameLocalName = nameLocalName
          , nameNamespace = Just ns
          , namePrefix    = Nothing
          }

    goNode :: Node -> Node
    goNode (NodeElement e) = NodeElement $ addNS ns e
    goNode n               = n

-- | The main namespace for Excel
mainNamespace :: Text
mainNamespace = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
