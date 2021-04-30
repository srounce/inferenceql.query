(ns inferenceql.query.lang.condition
  (:require [inferenceql.inference.gpm :as gpm]
            [inferenceql.query.lang.eval :as eval]
            [inferenceql.query.parser.tree :as tree]
            [medley.core :as medley]))

(defmethod eval/eval :conditioned-by-expr
  [node env]
  (let [model (-> node
                  (tree/get-node :model-expr)
                  (eval/eval env))
        conditions (-> node
                       (tree/get-node :conditioning-event-expr)
                       (eval/eval env))]
    (gpm/condition model conditions)))

(defmethod eval/eval :conditioning-event-expr
  [node env]
  (let [[child-node] (tree/children node)
        m (eval/eval child-node env)]
    (medley/remove-vals #{:iql/no-value} m)))

(defmethod eval/eval :env-event-expr
  [node env]
  (let [k (eval/eval-child-in node env [:nilable-ref :name])]
    (if-let [
             v (-> (tree/only-child node)
                   (eval/eval env))]
      {k v}
      {})))

(defmethod eval/eval :conditioning-conjunction-expr
  [node env]
  (->> (tree/child-nodes node)
       (map #(eval/eval % env))
       (into {})))

(defmethod eval/eval :equivalence-relation-expr
  [node env]
  (let [[variable-expr value-expr] (tree/child-nodes node)
        variable (eval/eval variable-expr env)
        value (case (tree/tag value-expr)
                :variable-expr (let [var-name (eval/eval value-expr env)]
                                 (get env var-name))
                (eval/eval value-expr env))]
    {variable value}))