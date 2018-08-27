{-# LANGUAGE RecordWildCards #-}

module Web.SCIM.Schema.ListResponse (ListResponse, fromList) where

import Data.Aeson
import GHC.Generics (Generic)
import Web.SCIM.Schema.Common
import Web.SCIM.Schema.Schema

data ListResponse a = ListResponse
  { schemas :: [Schema]
  , totalResults :: Int
  , resources :: [a]
  } deriving (Show, Eq, Generic)

fromList :: [a] -> ListResponse a
fromList list = ListResponse
  { schemas = [ListResponse2_0]
  , totalResults = length list
  , resources = list
  }

instance FromJSON a => FromJSON (ListResponse a) where
  parseJSON = genericParseJSON parseOptions . jsonLower

instance ToJSON a => ToJSON (ListResponse a) where
  toJSON ListResponse{..} =
    object [ "Resources" .= resources
           , "schemas" .= schemas
           , "totalResults" .= totalResults
           ]

